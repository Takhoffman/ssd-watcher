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

enum DiscoveryEvidence: String, Codable, Hashable, CaseIterable {
    case validatedDatabase
    case liveCodexProcess
    case configuration
    case sessions
    case skillsOrRules
    case matchingFilename
    case explicitSelection

    var label: String {
        switch self {
        case .validatedDatabase: "Verified Codex database"
        case .liveCodexProcess: "Open in a Codex process"
        case .configuration: "Codex configuration"
        case .sessions: "Session history"
        case .skillsOrRules: "Skills or rules"
        case .matchingFilename: "Matching database filename"
        case .explicitSelection: "Added by you"
        }
    }
}

struct HomeCandidate: Identifiable, Hashable {
    let rootURL: URL
    let databaseURLs: [URL]
    let evidence: Set<DiscoveryEvidence>
    let confidence: Double

    var id: String { rootURL.standardizedFileURL.path }

    var primaryDatabase: URL {
        databaseURLs.max { lhs, rhs in
            let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return leftDate < rightDate
        } ?? rootURL.appendingPathComponent("logs_2.sqlite")
    }
}

struct DatabaseSample: Equatable {
    let timestamp: Date
    let sequence: Int64
    let totalBytes: Int64
}

struct RatePoint: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

struct HomeMetrics: Equatable {
    var sequence: Int64
    var totalBytes: Int64
    var insertRate: Double
    var growthBytesPerSecond: Double
    var lastUpdated: Date

    static func initial(sample: DatabaseSample) -> HomeMetrics {
        HomeMetrics(
            sequence: sample.sequence,
            totalBytes: sample.totalBytes,
            insertRate: 0,
            growthBytesPerSecond: 0,
            lastUpdated: sample.timestamp
        )
    }
}

struct MonitoredHome: Identifiable, Equatable {
    let candidate: HomeCandidate
    var metrics: HomeMetrics
    var health: HealthLevel
    var history: [RatePoint]

    init(candidate: HomeCandidate, metrics: HomeMetrics, health: HealthLevel = .unknown, history: [RatePoint] = []) {
        self.candidate = candidate
        self.metrics = metrics
        self.health = health
        self.history = history
    }

    var id: String { candidate.id }

    var displayName: String {
        let name = candidate.rootURL.lastPathComponent
        if name == ".codex" { return "Default Codex" }
        return name.replacingOccurrences(of: ".codex-", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
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
}

enum HealthClassifier {
    static func classify(
        insertRate: Double,
        growthBytesPerSecond: Double,
        warningInsertRate: Double,
        criticalInsertRate: Double
    ) -> HealthLevel {
        if insertRate >= criticalInsertRate || growthBytesPerSecond >= 10 * 1_024 * 1_024 {
            return .critical
        }
        if insertRate >= warningInsertRate || growthBytesPerSecond >= 1 * 1_024 * 1_024 {
            return .elevated
        }
        return .healthy
    }
}
