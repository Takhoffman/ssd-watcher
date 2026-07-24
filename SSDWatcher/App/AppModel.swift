import AppKit
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var locations: [MonitoredLocation] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastScan: Date?
    @Published private(set) var availableDiskBytes: Int64?
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }
    @Published var scanInterval: TimeInterval {
        didSet {
            defaults.set(scanInterval, forKey: Keys.scanInterval)
            restartTimer()
        }
    }
    @Published var warningRecordRate: Double {
        didSet { defaults.set(warningRecordRate, forKey: Keys.warningRate) }
    }
    @Published var criticalRecordRate: Double {
        didSet { defaults.set(criticalRecordRate, forKey: Keys.criticalRate) }
    }
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notifications) }
    }
    @Published private(set) var customHomePaths: [String]
    @Published private(set) var launchAtLoginEnabled = false

    var overallHealth: HealthLevel {
        locations.map(\.health).max() ?? .unknown
    }

    var totalDatabaseBytes: Int64 {
        locations.reduce(0) { $0 + $1.metrics.totalBytes }
    }

    var activeLocationCount: Int {
        locations.filter {
            $0.metrics.recordRate > 0 || $0.metrics.growthBytesPerSecond > 0
        }.count
    }

    var monitoredProductCount: Int {
        Set(locations.map(\.candidate.product)).count
    }

    private let defaults: UserDefaults
    private let discovery = StorageDiscovery()
    private let notificationService = NotificationService()
    private let updateService = UpdateService()
    private var timer: Timer?
    private var previousSamples: [String: DatabaseSample] = [:]
    private var histories: [String: [RatePoint]] = [:]
    private var previousHealth: [String: HealthLevel] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        scanInterval = defaults.object(forKey: Keys.scanInterval) as? Double ?? 10
        warningRecordRate = defaults.object(forKey: Keys.warningRate) as? Double
            ?? defaults.object(forKey: Keys.legacyWarningRate) as? Double
            ?? 100
        criticalRecordRate = defaults.object(forKey: Keys.criticalRate) as? Double
            ?? defaults.object(forKey: Keys.legacyCriticalRate) as? Double
            ?? 1_000
        notificationsEnabled = defaults.object(forKey: Keys.notifications) as? Bool ?? true
        customHomePaths = defaults.stringArray(forKey: Keys.customPaths) ?? []

        refreshLaunchAtLoginState()
        scan()
        restartTimer()
    }

    deinit {
        timer?.invalidate()
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true

        let customPaths = customHomePaths
        DispatchQueue.global(qos: .utility).async { [discovery] in
            let detected = discovery.discover(customPaths: customPaths)
            let snapshots = detected.compactMap { candidate -> MonitoredLocation? in
                guard let sample = DatabaseProbe.sample(candidate: candidate) else {
                    return nil
                }
                return MonitoredLocation(candidate: candidate, metrics: .initial(sample: sample))
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.mergeInitialSnapshots(snapshots)
                self.isScanning = false
                self.lastScan = Date()
                self.refreshDiskCapacity()
            }
        }
    }

    func sampleNow() {
        guard !locations.isEmpty else {
            scan()
            return
        }

        let candidates = locations.map(\.candidate)
        DispatchQueue.global(qos: .utility).async {
            let samples = candidates.compactMap { candidate -> (String, DatabaseSample)? in
                guard let sample = DatabaseProbe.sample(candidate: candidate) else {
                    return nil
                }
                return (candidate.id, sample)
            }

            DispatchQueue.main.async { [weak self] in
                self?.apply(samples: Dictionary(uniqueKeysWithValues: samples))
            }
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        if notificationsEnabled {
            notificationService.requestAuthorization()
        }
    }

    func requestNotificationPermission() {
        notificationsEnabled = true
        notificationService.requestAuthorization()
    }

    func chooseCustomHome() {
        let panel = NSOpenPanel()
        panel.title = "Choose an agent data folder"
        panel.message = "Select a Codex, OpenClaw, or Hermes data folder. SSD Watcher will verify its databases before monitoring."
        panel.prompt = "Monitor Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        addCustomHome(path: url.standardizedFileURL.path)
    }

    func addCustomHome(path: String) {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !customHomePaths.contains(normalized) else { return }
        customHomePaths.append(normalized)
        defaults.set(customHomePaths, forKey: Keys.customPaths)
        scan()
    }

    func removeCustomHome(path: String) {
        customHomePaths.removeAll { $0 == path }
        defaults.set(customHomePaths, forKey: Keys.customPaths)
        scan()
    }

    func reveal(_ location: MonitoredLocation) {
        NSWorkspace.shared.activateFileViewerSelecting([location.candidate.primaryDatabase])
    }

    func openActivityMonitor() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"),
            configuration: .init()
        )
    }

    func checkForUpdates() {
        updateService.checkForUpdates()
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            return
        }
        refreshLaunchAtLoginState()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func restartTimer() {
        timer?.invalidate()
        guard scanInterval > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sampleNow()
            }
        }
        timer?.tolerance = min(2, scanInterval * 0.15)
    }

    private func mergeInitialSnapshots(_ snapshots: [MonitoredLocation]) {
        var updated: [MonitoredLocation] = []

        for var location in snapshots {
            if let existing = locations.first(where: { $0.id == location.id }) {
                location.metrics = existing.metrics
                location.history = existing.history
            } else if let sample = DatabaseProbe.sample(candidate: location.candidate) {
                previousSamples[location.id] = sample
            }
            updated.append(location)
        }

        locations = updated.sorted {
            if $0.health != $1.health { return $0.health > $1.health }
            if $0.metrics.recordRate != $1.metrics.recordRate {
                return $0.metrics.recordRate > $1.metrics.recordRate
            }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        sampleNow()
    }

    private func apply(samples: [String: DatabaseSample]) {
        let now = Date()

        locations = locations.map { existing in
            guard let sample = samples[existing.id] else {
                var unavailable = existing
                unavailable.health = .unknown
                return unavailable
            }

            let previous = previousSamples[existing.id]
            let elapsed = max(sample.timestamp.timeIntervalSince(previous?.timestamp ?? sample.timestamp), 0)
            let counterDelta = max(
                0,
                sample.activityCounter - (previous?.activityCounter ?? sample.activityCounter)
            )
            let byteDelta = max(0, sample.totalBytes - (previous?.totalBytes ?? sample.totalBytes))
            let recordRate = elapsed > 0 ? Double(counterDelta) / elapsed : 0
            let growthRate = elapsed > 0 ? Double(byteDelta) / elapsed : 0

            var history = histories[existing.id] ?? existing.history
            history.append(RatePoint(timestamp: now, value: recordRate))
            history = Array(history.suffix(36))
            histories[existing.id] = history

            let health = HealthClassifier.classify(
                recordRate: recordRate,
                growthBytesPerSecond: growthRate,
                warningRecordRate: warningRecordRate,
                criticalRecordRate: criticalRecordRate
            )

            var updated = existing
            updated.metrics = LocationMetrics(
                activityCounter: sample.activityCounter,
                totalBytes: sample.totalBytes,
                recordRate: recordRate,
                growthBytesPerSecond: growthRate,
                lastUpdated: sample.timestamp
            )
            updated.health = health
            updated.history = history

            if notificationsEnabled,
               health >= .elevated,
               previousHealth[existing.id, default: .healthy] < health {
                notificationService.notify(location: updated)
            }
            previousHealth[existing.id] = health
            previousSamples[existing.id] = sample
            return updated
        }

        locations.sort {
            if $0.health != $1.health { return $0.health > $1.health }
            if $0.metrics.recordRate != $1.metrics.recordRate {
                return $0.metrics.recordRate > $1.metrics.recordRate
            }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        refreshDiskCapacity()
    }

    private func refreshDiskCapacity() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        availableDiskBytes = values?.volumeAvailableCapacityForImportantUsage
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    private enum Keys {
        static let onboarding = "hasCompletedOnboarding"
        static let scanInterval = "scanInterval"
        static let warningRate = "warningRecordRate"
        static let criticalRate = "criticalRecordRate"
        static let legacyWarningRate = "warningInsertRate"
        static let legacyCriticalRate = "criticalInsertRate"
        static let notifications = "notificationsEnabled"
        static let customPaths = "customHomePaths"
    }
}
