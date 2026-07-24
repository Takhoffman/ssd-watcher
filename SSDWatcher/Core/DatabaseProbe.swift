import Foundation
import SQLite3

enum DatabaseProbe {
    static func isCodexLogDatabase(_ url: URL) -> Bool {
        guard url.lastPathComponent.range(
            of: #"^logs_[0-9]+\.sqlite$"#,
            options: .regularExpression
        ) != nil else {
            return false
        }

        guard let database = openReadOnly(url) else { return false }
        defer { sqlite3_close(database) }

        guard tableExists("logs", in: database) else { return false }
        let columns = columnNames(table: "logs", in: database)
        return columns.contains("id")
            && columns.contains("ts")
            && (columns.contains("target") || columns.contains("message"))
    }

    static func sample(candidate: HomeCandidate) -> DatabaseSample? {
        var totalBytes: Int64 = 0
        var maximumSequence: Int64 = 0
        var sampledAtLeastOneDatabase = false

        for databaseURL in candidate.databaseURLs {
            guard let database = openReadOnly(databaseURL) else { continue }
            defer { sqlite3_close(database) }

            guard tableExists("logs", in: database) else { continue }
            sampledAtLeastOneDatabase = true
            maximumSequence += sequence(in: database)
            totalBytes += fileSetSize(for: databaseURL)
        }

        guard sampledAtLeastOneDatabase else { return nil }
        return DatabaseSample(
            timestamp: Date(),
            sequence: maximumSequence,
            totalBytes: totalBytes
        )
    }

    private static func openReadOnly(_ url: URL) -> OpaquePointer? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            return nil
        }
        sqlite3_busy_timeout(database, 250)
        return database
    }

    private static func tableExists(_ table: String, in database: OpaquePointer) -> Bool {
        let allowedTables = ["logs"]
        guard allowedTables.contains(table) else { return false }
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name='\(table)' LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func columnNames(table: String, in database: OpaquePointer) -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var columns: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let value = sqlite3_column_text(statement, 1) else { continue }
            columns.insert(String(cString: value))
        }
        return columns
    }

    private static func sequence(in database: OpaquePointer) -> Int64 {
        let sql = "SELECT seq FROM sqlite_sequence WHERE name='logs' LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int64(statement, 0)
    }

    private static func fileSetSize(for databaseURL: URL) -> Int64 {
        let paths = [
            databaseURL.path,
            databaseURL.path + "-wal",
            databaseURL.path + "-shm",
        ]

        return paths.reduce(0) { total, path in
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? NSNumber else {
                return total
            }
            return total + size.int64Value
        }
    }
}
