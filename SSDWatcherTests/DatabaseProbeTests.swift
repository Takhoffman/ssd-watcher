import SQLite3
import XCTest
@testable import SSDWatcher

final class DatabaseProbeTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SSDWatcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testRecognizesAndSamplesCodexLogSchema() throws {
        let databaseURL = temporaryDirectory.appendingPathComponent("logs_2.sqlite")
        try execute(
            """
            CREATE TABLE logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts INTEGER NOT NULL,
                target TEXT,
                level TEXT,
                message TEXT,
                thread_id TEXT
            );
            INSERT INTO logs (ts, target, level, message) VALUES
                (1, 'test', 'INFO', 'fixture'),
                (2, 'test', 'INFO', 'fixture'),
                (3, 'test', 'INFO', 'fixture');
            """,
            at: databaseURL
        )

        XCTAssertEqual(DatabaseProbe.classify(databaseURL), .codexLog)

        let candidate = StorageCandidate(
            product: .codex,
            rootURL: temporaryDirectory,
            databases: [DatabaseTarget(url: databaseURL, kind: .codexLog)],
            evidence: [.matchingFilename, .validatedDatabase],
            confidence: 0.8
        )
        let sample = try XCTUnwrap(DatabaseProbe.sample(candidate: candidate))
        XCTAssertEqual(sample.activityCounter, 3)
        XCTAssertGreaterThan(sample.totalBytes, 0)
    }

    func testRecognizesCurrentOpenClawGlobalAndAgentStores() throws {
        let globalURL = temporaryDirectory.appendingPathComponent("openclaw.sqlite")
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
            CREATE TABLE audit_events (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id TEXT
            );
            INSERT INTO audit_events (event_id) VALUES ('a'), ('b');
            """,
            at: globalURL
        )

        let agentURL = temporaryDirectory.appendingPathComponent("openclaw-agent.sqlite")
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
                session_id TEXT NOT NULL,
                seq INTEGER NOT NULL,
                event_json TEXT NOT NULL,
                PRIMARY KEY (session_id, seq)
            );
            INSERT INTO transcript_events VALUES
                ('session-a', 1, '{}'),
                ('session-a', 2, '{}'),
                ('session-b', 1, '{}');
            """,
            at: agentURL
        )

        XCTAssertEqual(DatabaseProbe.classify(globalURL), .openClawGlobal)
        XCTAssertEqual(DatabaseProbe.classify(agentURL), .openClawAgent)

        let candidate = StorageCandidate(
            product: .openClaw,
            rootURL: temporaryDirectory,
            databases: [
                DatabaseTarget(url: globalURL, kind: .openClawGlobal),
                DatabaseTarget(url: agentURL, kind: .openClawAgent),
            ],
            evidence: [.validatedDatabase],
            confidence: 0.8
        )
        XCTAssertEqual(DatabaseProbe.sample(candidate: candidate)?.activityCounter, 5)
    }

    func testRecognizesHermesStateWithoutTrustingGenericFilename() throws {
        let databaseURL = temporaryDirectory.appendingPathComponent("state.db")
        try createHermesStateDatabase(at: databaseURL, messageCount: 4)

        XCTAssertEqual(DatabaseProbe.classify(databaseURL), .hermesState)

        let unrelatedURL = temporaryDirectory.appendingPathComponent("unrelated-state.db")
        try execute("CREATE TABLE sessions (id TEXT PRIMARY KEY);", at: unrelatedURL)
        XCTAssertNil(DatabaseProbe.classify(unrelatedURL))
    }

    func testRecognizesLegacyOpenClawMemoryIndex() throws {
        let databaseURL = temporaryDirectory.appendingPathComponent("main.sqlite")
        try execute(
            """
            CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE files (
                path TEXT PRIMARY KEY,
                source TEXT NOT NULL DEFAULT 'memory',
                hash TEXT NOT NULL,
                mtime INTEGER NOT NULL,
                size INTEGER NOT NULL
            );
            CREATE TABLE chunks (
                id TEXT PRIMARY KEY,
                path TEXT NOT NULL,
                source TEXT NOT NULL DEFAULT 'memory',
                start_line INTEGER NOT NULL,
                end_line INTEGER NOT NULL,
                hash TEXT NOT NULL,
                model TEXT NOT NULL,
                text TEXT NOT NULL,
                embedding TEXT NOT NULL,
                updated_at INTEGER NOT NULL
            );
            """,
            at: databaseURL
        )

        XCTAssertEqual(DatabaseProbe.classify(databaseURL), .openClawLegacyMemory)
    }

    func testHealthClassificationUsesRecordsAndGrowth() {
        XCTAssertEqual(
            HealthClassifier.classify(
                recordRate: 3,
                growthBytesPerSecond: 0,
                warningRecordRate: 100,
                criticalRecordRate: 1_000
            ),
            .healthy
        )
        XCTAssertEqual(
            HealthClassifier.classify(
                recordRate: 125,
                growthBytesPerSecond: 0,
                warningRecordRate: 100,
                criticalRecordRate: 1_000
            ),
            .elevated
        )
        XCTAssertEqual(
            HealthClassifier.classify(
                recordRate: 0,
                growthBytesPerSecond: 11 * 1_024 * 1_024,
                warningRecordRate: 100,
                criticalRecordRate: 1_000
            ),
            .critical
        )
    }

    private func createHermesStateDatabase(at url: URL, messageCount: Int) throws {
        var inserts = ""
        for index in 0..<messageCount {
            inserts += """
            INSERT INTO messages (session_id, role, content, timestamp)
            VALUES ('session', 'user', 'fixture-\(index)', \(index));

            """
        }
        try execute(
            """
            CREATE TABLE schema_version (version INTEGER NOT NULL);
            INSERT INTO schema_version VALUES (23);
            CREATE TABLE sessions (
                id TEXT PRIMARY KEY,
                source TEXT NOT NULL,
                started_at REAL NOT NULL
            );
            INSERT INTO sessions VALUES ('session', 'cli', 0);
            CREATE TABLE messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT,
                timestamp REAL NOT NULL
            );
            CREATE TABLE state_meta (key TEXT PRIMARY KEY, value TEXT);
            \(inserts)
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
