import SQLite3
import XCTest
@testable import SSDWatcher

final class DiscoveryTests: XCTestCase {
    func testExplicitRenamedHomeIsDiscoveredByFingerprint() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("unrelated-folder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data().write(to: root.appendingPathComponent("config.toml"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("sessions"),
            withIntermediateDirectories: true
        )
        try createLogDatabase(at: root.appendingPathComponent("logs_7.sqlite"))

        let result = CodexHomeDiscovery().discover(
            customPaths: [root.path],
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            includeRuntimeSources: false
        )
        let candidate = try XCTUnwrap(result.first { $0.rootURL.standardizedFileURL == root.standardizedFileURL })

        XCTAssertTrue(candidate.evidence.contains(.validatedDatabase))
        XCTAssertTrue(candidate.evidence.contains(.explicitSelection))
        XCTAssertTrue(candidate.evidence.contains(.configuration))
        XCTAssertGreaterThanOrEqual(candidate.confidence, 0.9)
    }

    func testLegacySQLiteFolderIsGroupedWithItsCodexHome() throws {
        let fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("SSDWatcherFakeHome-\(UUID().uuidString)", isDirectory: true)
        let codex = fakeHome.appendingPathComponent(".codex", isDirectory: true)
        let legacy = codex.appendingPathComponent("sqlite", isDirectory: true)
        let profiles = fakeHome.appendingPathComponent(".codex-profiles", isDirectory: true)
        let alternate = profiles.appendingPathComponent("renamed-work", isDirectory: true)

        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: alternate, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fakeHome) }

        try Data().write(to: codex.appendingPathComponent("config.toml"))
        try Data().write(to: alternate.appendingPathComponent("config.toml"))
        try createLogDatabase(at: codex.appendingPathComponent("logs_2.sqlite"))
        try createLogDatabase(at: legacy.appendingPathComponent("logs_1.sqlite"))
        try createLogDatabase(at: alternate.appendingPathComponent("logs_9.sqlite"))

        let result = CodexHomeDiscovery().discover(
            customPaths: [],
            homeDirectory: fakeHome,
            includeRuntimeSources: false
        )

        XCTAssertEqual(result.count, 2)
        let defaultHome = try XCTUnwrap(result.first { $0.rootURL.standardizedFileURL == codex.standardizedFileURL })
        XCTAssertEqual(defaultHome.databaseURLs.count, 2)
        XCTAssertFalse(result.contains { $0.rootURL.standardizedFileURL == legacy.standardizedFileURL })
        XCTAssertTrue(result.contains { $0.rootURL.standardizedFileURL == alternate.standardizedFileURL })
    }

    private func createLogDatabase(at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { sqlite3_close(database) }

        let sql = """
        CREATE TABLE logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            target TEXT,
            message TEXT
        );
        INSERT INTO logs (ts, target, message) VALUES (1, 'fixture', 'fixture');
        """
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
    }
}
