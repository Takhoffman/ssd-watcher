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

    func testRecognizesCodexLogSchema() throws {
        let databaseURL = try makeLogDatabase(rowCount: 3)

        XCTAssertTrue(DatabaseProbe.isCodexLogDatabase(databaseURL))

        let candidate = HomeCandidate(
            rootURL: temporaryDirectory,
            databaseURLs: [databaseURL],
            evidence: [.matchingFilename, .validatedDatabase],
            confidence: 0.8
        )
        let sample = try XCTUnwrap(DatabaseProbe.sample(candidate: candidate))
        XCTAssertEqual(sample.sequence, 3)
        XCTAssertGreaterThan(sample.totalBytes, 0)
    }

    func testRejectsUnrelatedSQLiteDatabase() throws {
        let databaseURL = temporaryDirectory.appendingPathComponent("logs_2.sqlite")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE unrelated (value TEXT)", nil, nil, nil), SQLITE_OK)

        XCTAssertFalse(DatabaseProbe.isCodexLogDatabase(databaseURL))
    }

    func testHealthClassification() {
        XCTAssertEqual(
            HealthClassifier.classify(
                insertRate: 3,
                growthBytesPerSecond: 0,
                warningInsertRate: 100,
                criticalInsertRate: 1_000
            ),
            .healthy
        )
        XCTAssertEqual(
            HealthClassifier.classify(
                insertRate: 125,
                growthBytesPerSecond: 0,
                warningInsertRate: 100,
                criticalInsertRate: 1_000
            ),
            .elevated
        )
        XCTAssertEqual(
            HealthClassifier.classify(
                insertRate: 2_400,
                growthBytesPerSecond: 0,
                warningInsertRate: 100,
                criticalInsertRate: 1_000
            ),
            .critical
        )
    }

    @discardableResult
    private func makeLogDatabase(rowCount: Int) throws -> URL {
        let databaseURL = temporaryDirectory.appendingPathComponent("logs_2.sqlite")
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { sqlite3_close(database) }

        let schema = """
        CREATE TABLE logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            target TEXT,
            level TEXT,
            message TEXT,
            thread_id TEXT
        );
        """
        XCTAssertEqual(sqlite3_exec(database, schema, nil, nil, nil), SQLITE_OK)

        for index in 0..<rowCount {
            let insert = "INSERT INTO logs (ts, target, level, message) VALUES (\(index), 'test', 'INFO', 'fixture')"
            XCTAssertEqual(sqlite3_exec(database, insert, nil, nil, nil), SQLITE_OK)
        }

        return databaseURL
    }
}
