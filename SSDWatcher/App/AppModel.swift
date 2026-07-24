import AppKit
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var homes: [MonitoredHome] = []
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
    @Published var warningInsertRate: Double {
        didSet { defaults.set(warningInsertRate, forKey: Keys.warningRate) }
    }
    @Published var criticalInsertRate: Double {
        didSet { defaults.set(criticalInsertRate, forKey: Keys.criticalRate) }
    }
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notifications) }
    }
    @Published private(set) var customHomePaths: [String]
    @Published private(set) var launchAtLoginEnabled = false

    var overallHealth: HealthLevel {
        homes.map(\.health).max() ?? .unknown
    }

    var totalDatabaseBytes: Int64 {
        homes.reduce(0) { $0 + $1.metrics.totalBytes }
    }

    var activeHomeCount: Int {
        homes.filter { $0.metrics.insertRate > 0 }.count
    }

    private let defaults: UserDefaults
    private let discovery = CodexHomeDiscovery()
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
        warningInsertRate = defaults.object(forKey: Keys.warningRate) as? Double ?? 100
        criticalInsertRate = defaults.object(forKey: Keys.criticalRate) as? Double ?? 1_000
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
            let snapshots = detected.compactMap { candidate -> MonitoredHome? in
                guard let sample = DatabaseProbe.sample(candidate: candidate) else {
                    return nil
                }
                return MonitoredHome(candidate: candidate, metrics: .initial(sample: sample))
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
        guard !homes.isEmpty else {
            scan()
            return
        }

        let candidates = homes.map(\.candidate)
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
        panel.title = "Choose a Codex home"
        panel.message = "Select the folder that contains Codex configuration, sessions, or SQLite log databases."
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

    func reveal(_ home: MonitoredHome) {
        NSWorkspace.shared.activateFileViewerSelecting([home.candidate.primaryDatabase])
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

    private func mergeInitialSnapshots(_ snapshots: [MonitoredHome]) {
        var updated: [MonitoredHome] = []

        for var home in snapshots {
            if let existing = homes.first(where: { $0.id == home.id }) {
                home.metrics = existing.metrics
                home.history = existing.history
            } else if let sample = DatabaseProbe.sample(candidate: home.candidate) {
                previousSamples[home.id] = sample
            }
            updated.append(home)
        }

        homes = updated.sorted {
            if $0.health != $1.health { return $0.health > $1.health }
            if $0.metrics.insertRate != $1.metrics.insertRate {
                return $0.metrics.insertRate > $1.metrics.insertRate
            }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        sampleNow()
    }

    private func apply(samples: [String: DatabaseSample]) {
        let now = Date()

        homes = homes.map { existing in
            guard let sample = samples[existing.id] else {
                var unavailable = existing
                unavailable.health = .unknown
                return unavailable
            }

            let previous = previousSamples[existing.id]
            let elapsed = max(sample.timestamp.timeIntervalSince(previous?.timestamp ?? sample.timestamp), 0)
            let sequenceDelta = max(0, sample.sequence - (previous?.sequence ?? sample.sequence))
            let byteDelta = max(0, sample.totalBytes - (previous?.totalBytes ?? sample.totalBytes))
            let insertRate = elapsed > 0 ? Double(sequenceDelta) / elapsed : 0
            let growthRate = elapsed > 0 ? Double(byteDelta) / elapsed : 0

            var history = histories[existing.id] ?? existing.history
            history.append(RatePoint(timestamp: now, value: insertRate))
            history = Array(history.suffix(36))
            histories[existing.id] = history

            let health = HealthClassifier.classify(
                insertRate: insertRate,
                growthBytesPerSecond: growthRate,
                warningInsertRate: warningInsertRate,
                criticalInsertRate: criticalInsertRate
            )

            var updated = existing
            updated.metrics = HomeMetrics(
                sequence: sample.sequence,
                totalBytes: sample.totalBytes,
                insertRate: insertRate,
                growthBytesPerSecond: growthRate,
                lastUpdated: sample.timestamp
            )
            updated.health = health
            updated.history = history

            if notificationsEnabled,
               health >= .elevated,
               previousHealth[existing.id, default: .healthy] < health {
                notificationService.notify(home: updated)
            }
            previousHealth[existing.id] = health
            previousSamples[existing.id] = sample
            return updated
        }

        homes.sort {
            if $0.health != $1.health { return $0.health > $1.health }
            if $0.metrics.insertRate != $1.metrics.insertRate {
                return $0.metrics.insertRate > $1.metrics.insertRate
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
        static let warningRate = "warningInsertRate"
        static let criticalRate = "criticalInsertRate"
        static let notifications = "notificationsEnabled"
        static let customPaths = "customHomePaths"
    }
}
