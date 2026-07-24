import SQLite3
import XCTest
@testable import SSDWatcher

final class DiscoveryTests: XCTestCase {
    func testExplicitRenamedCodexHomeIsDiscoveredByFingerprint() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("unrelated-folder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data().write(to: root.appendingPathComponent("config.toml"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("sessions"),
            withIntermediateDirectories: true
        )
        try createCodexDatabase(at: root.appendingPathComponent("logs_7.sqlite"))

        let result = StorageDiscovery().discover(
            customPaths: [root.path],
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            includeRuntimeSources: false
        )
        let candidate = try XCTUnwrap(result.first {
            $0.product == .codex
                && $0.rootURL.standardizedFileURL == root.standardizedFileURL
        })

        XCTAssertTrue(candidate.evidence.contains(.validatedDatabase))
        XCTAssertTrue(candidate.evidence.contains(.explicitSelection))
        XCTAssertTrue(candidate.evidence.contains(.configuration))
        XCTAssertGreaterThanOrEqual(candidate.confidence, 0.9)
    }

    func testDiscoversOpenClawAgentsAndHermesProfilesAsCoherentLocations() throws {
        let fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("SSDWatcherFakeHome-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fakeHome) }

        let openClaw = fakeHome.appendingPathComponent(".openclaw-work", isDirectory: true)
        try FileManager.default.createDirectory(
            at: openClaw.appendingPathComponent("state"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: openClaw.appendingPathComponent("agents/main/agent"),
            withIntermediateDirectories: true
        )
        try Data().write(to: openClaw.appendingPathComponent("openclaw.json"))
        try createOpenClawGlobalDatabase(
            at: openClaw.appendingPathComponent("state/openclaw.sqlite")
        )
        try createOpenClawAgentDatabase(
            at: openClaw.appendingPathComponent("agents/main/agent/openclaw-agent.sqlite")
        )

        let hermes = fakeHome.appendingPathComponent(".hermes", isDirectory: true)
        let profile = hermes.appendingPathComponent("profiles/writer", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try Data().write(to: hermes.appendingPathComponent("config.yaml"))
        try Data().write(to: profile.appendingPathComponent("config.yaml"))
        try createHermesStateDatabase(at: hermes.appendingPathComponent("state.db"))
        try createHermesStateDatabase(at: profile.appendingPathComponent("state.db"))

        let result = StorageDiscovery().discover(
            customPaths: [],
            homeDirectory: fakeHome,
            includeRuntimeSources: false
        )

        let openClawCandidate = try XCTUnwrap(result.first {
            $0.product == .openClaw
                && $0.rootURL.standardizedFileURL == openClaw.standardizedFileURL
        })
        XCTAssertEqual(openClawCandidate.databases.count, 2)

        XCTAssertNotNil(result.first {
            $0.product == .hermes
                && $0.rootURL.standardizedFileURL == hermes.standardizedFileURL
        })
        XCTAssertNotNil(result.first {
            $0.product == .hermes
                && $0.rootURL.standardizedFileURL == profile.standardizedFileURL
        })
    }

    func testLegacyCodexSQLiteFolderIsGroupedWithItsHome() throws {
        let fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("SSDWatcherCodexHome-\(UUID().uuidString)", isDirectory: true)
        let codex = fakeHome.appendingPathComponent(".codex", isDirectory: true)
        let legacy = codex.appendingPathComponent("sqlite", isDirectory: true)

        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fakeHome) }

        try createCodexDatabase(at: codex.appendingPathComponent("logs_2.sqlite"))
        try createCodexDatabase(at: legacy.appendingPathComponent("logs_1.sqlite"))

        let result = StorageDiscovery().discover(
            customPaths: [],
            homeDirectory: fakeHome,
            includeRuntimeSources: false
        )

        let candidate = try XCTUnwrap(result.first {
            $0.product == .codex
                && $0.rootURL.standardizedFileURL == codex.standardizedFileURL
        })
        XCTAssertEqual(candidate.databases.count, 2)
        XCTAssertFalse(result.contains {
            $0.rootURL.standardizedFileURL == legacy.standardizedFileURL
        })
    }

    private func createCodexDatabase(at url: URL) throws {
        try execute(
            """
            CREATE TABLE logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts INTEGER NOT NULL,
                target TEXT,
                message TEXT
            );
            INSERT INTO logs (ts, target, message) VALUES (1, 'fixture', 'fixture');
            """,
            at: url
        )
    }

    private func createOpenClawGlobalDatabase(at url: URL) throws {
        try execute(
            """
            CREATE TABLE schema_meta (
                meta_key TEXT PRIMARY KEY,
                role TEXT NOT NULL,
                schema_version INTEGER NOT NULL,
                agent_id TEXT,
                app_version TEXT,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );
            INSERT INTO schema_meta VALUES ('primary', 'global', 7, NULL, 'fixture', 1, 1);
            CREATE TABLE agent_databases (agent_id TEXT, path TEXT);
            CREATE TABLE plugin_state_entries (plugin_id TEXT, namespace TEXT, key TEXT);
            """,
            at: url
        )
    }

    private func createOpenClawAgentDatabase(at url: URL) throws {
        try execute(
            """
            CREATE TABLE schema_meta (
                meta_key TEXT PRIMARY KEY,
                role TEXT NOT NULL,
                schema_version INTEGER NOT NULL,
                agent_id TEXT,
                app_version TEXT,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );
            INSERT INTO schema_meta VALUES ('primary', 'agent', 13, 'main', 'fixture', 1, 1);
            CREATE TABLE session_nodes (session_key TEXT PRIMARY KEY);
            CREATE TABLE transcript_events (
                session_id TEXT,
                seq INTEGER,
                event_json TEXT,
                PRIMARY KEY (session_id, seq)
            );
            """,
            at: url
        )
    }

    private func createHermesStateDatabase(at url: URL) throws {
        try execute(
            """
            CREATE TABLE schema_version (version INTEGER NOT NULL);
            CREATE TABLE sessions (
                id TEXT PRIMARY KEY,
                source TEXT NOT NULL,
                started_at REAL NOT NULL
            );
            CREATE TABLE messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT,
                timestamp REAL NOT NULL
            );
            CREATE TABLE state_meta (key TEXT PRIMARY KEY, value TEXT);
            """,
            at: url
        )
    }

    private func execute(_ sql: String, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
    }
}
