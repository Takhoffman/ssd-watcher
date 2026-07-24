import Foundation
import SwiftUI

enum HealthLevel: Int, Comparable, Codable, CaseIterable {
    case unknown = 0
    case healthy = 1
    case elevated = 2
    case critical = 3

    static func < (lhs: HealthLevel, rhs: HealthLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .unknown: "Checking"
        case .healthy: "Healthy"
        case .elevated: "Elevated"
        case .critical: "Critical"
        }
    }

    var message: String {
        switch self {
        case .unknown: "Waiting for enough activity to establish a rate."
        case .healthy: "Write activity is within the expected range."
        case .elevated: "Write activity is unusually high and should be watched."
        case .critical: "Sustained write activity may rapidly consume SSD endurance."
        }
    }

    var systemImage: String {
        switch self {
        case .unknown: "circle.dotted"
        case .healthy: "checkmark.circle.fill"
        case .elevated: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }

    var menuBarSymbol: String {
        switch self {
        case .unknown: "externaldrive.badge.questionmark"
        case .healthy: "externaldrive.fill"
        case .elevated: "externaldrive.badge.exclamationmark"
        case .critical: "exclamationmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .unknown: .secondary
        case .healthy: DesignSystem.Colors.healthy
        case .elevated: DesignSystem.Colors.elevated
        case .critical: DesignSystem.Colors.critical
        }
    }
}

enum StorageProduct: String, Codable, Hashable, CaseIterable {
    case codex
    case openClaw
    case hermes

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .openClaw: "OpenClaw"
        case .hermes: "Hermes"
        }
    }

    var systemImage: String {
        switch self {
        case .codex: "terminal"
        case .openClaw: "pawprint.fill"
        case .hermes: "wing"
        }
    }
}

enum DatabaseKind: String, Codable, Hashable {
    case codexLog
    case openClawGlobal
    case openClawAgent
    case openClawLegacyMemory
    case hermesState
    case hermesMemory
    case hermesKanban
    case hermesProjects
    case hermesExecutions
    case hermesVerification

    var product: StorageProduct {
        switch self {
        case .codexLog:
            .codex
        case .openClawGlobal, .openClawAgent, .openClawLegacyMemory:
            .openClaw
        case .hermesState, .hermesMemory, .hermesKanban, .hermesProjects,
             .hermesExecutions, .hermesVerification:
            .hermes
        }
    }

    var displayName: String {
        switch self {
        case .codexLog: "Feedback log"
        case .openClawGlobal: "Shared state"
        case .openClawAgent: "Agent state"
        case .openClawLegacyMemory: "Legacy memory index"
        case .hermesState: "Sessions"
        case .hermesMemory: "Holographic memory"
        case .hermesKanban: "Kanban board"
        case .hermesProjects: "Projects"
        case .hermesExecutions: "Cron executions"
        case .hermesVerification: "Verification evidence"
        }
    }
}

struct DatabaseTarget: Identifiable, Hashable {
    let url: URL
    let kind: DatabaseKind

    var id: String { url.standardizedFileURL.path }
}

enum DiscoveryEvidence: String, Codable, Hashable, CaseIterable {
    case validatedDatabase
    case liveProcess
    case configuration
    case sessions
    case productFiles
    case matchingFilename
    case explicitSelection

    func label(for product: StorageProduct) -> String {
        switch self {
        case .validatedDatabase: "Verified \(product.displayName) database"
        case .liveProcess: "Open in a live \(product.displayName) process"
        case .configuration: "\(product.displayName) configuration"
        case .sessions: "Session history"
        case .productFiles: "\(product.displayName) data files"
        case .matchingFilename: "Matching database filename"
        case .explicitSelection: "Added by you"
        }
    }
}

struct StorageCandidate: Identifiable, Hashable {
    let product: StorageProduct
    let rootURL: URL
    let databases: [DatabaseTarget]
    let evidence: Set<DiscoveryEvidence>
    let confidence: Double

    var id: String { "\(product.rawValue):\(rootURL.standardizedFileURL.path)" }

    var primaryDatabase: URL {
        databases.max { lhs, rhs in
            let leftDate = (try? lhs.url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast
            let rightDate = (try? rhs.url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast
            return leftDate < rightDate
        }?.url ?? rootURL
    }
}

struct DatabaseSample: Equatable {
    let timestamp: Date
    let activityCounter: Int64
    let totalBytes: Int64
}

struct RatePoint: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

struct LocationMetrics: Equatable {
    var activityCounter: Int64
    var totalBytes: Int64
    var recordRate: Double
    var growthBytesPerSecond: Double
    var lastUpdated: Date

    static func initial(sample: DatabaseSample) -> LocationMetrics {
        LocationMetrics(
            activityCounter: sample.activityCounter,
            totalBytes: sample.totalBytes,
            recordRate: 0,
            growthBytesPerSecond: 0,
            lastUpdated: sample.timestamp
        )
    }
}

struct MonitoredLocation: Identifiable, Equatable {
    let candidate: StorageCandidate
    var metrics: LocationMetrics
    var health: HealthLevel
    var history: [RatePoint]

    init(
        candidate: StorageCandidate,
        metrics: LocationMetrics,
        health: HealthLevel = .unknown,
        history: [RatePoint] = []
    ) {
        self.candidate = candidate
        self.metrics = metrics
        self.health = health
        self.history = history
    }

    var id: String { candidate.id }

    var displayName: String {
        let name = candidate.rootURL.lastPathComponent
        switch candidate.product {
        case .codex:
            if name == ".codex" { return "Default Codex" }
            return cleaned(name, prefixes: [".codex-", "codex-"])
        case .openClaw:
            if name == ".openclaw" || name == ".clawdbot" { return "Default OpenClaw" }
            return cleaned(name, prefixes: [".openclaw-", "openclaw-", ".clawdbot-"])
        case .hermes:
            if name == ".hermes" { return "Default Hermes" }
            if candidate.rootURL.deletingLastPathComponent().lastPathComponent == "profiles" {
                return "\(cleaned(name, prefixes: [])) profile"
            }
            return cleaned(name, prefixes: [".hermes-", "hermes-"])
        }
    }

    var path: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fullPath = candidate.rootURL.path
        guard fullPath == home || fullPath.hasPrefix(home + "/") else {
            return fullPath
        }
        return "~" + fullPath.dropFirst(home.count)
    }

    var confidenceLabel: String {
        switch candidate.confidence {
        case 0.85...: "Verified"
        case 0.65...: "High confidence"
        default: "Probable"
        }
    }

    private func cleaned(_ name: String, prefixes: [String]) -> String {
        var result = name
        for prefix in prefixes where result.lowercased().hasPrefix(prefix) {
            result.removeFirst(prefix.count)
            break
        }
        result = result
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return result.isEmpty ? candidate.product.displayName : result.capitalized
    }
}

enum HealthClassifier {
    static func classify(
        recordRate: Double,
        growthBytesPerSecond: Double,
        warningRecordRate: Double,
        criticalRecordRate: Double
    ) -> HealthLevel {
        if recordRate >= criticalRecordRate || growthBytesPerSecond >= 10 * 1_024 * 1_024 {
            return .critical
        }
        if recordRate >= warningRecordRate || growthBytesPerSecond >= 1 * 1_024 * 1_024 {
            return .elevated
        }
        return .healthy
    }
}
