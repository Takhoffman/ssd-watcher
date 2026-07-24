import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DatabaseProbe {
    static func classify(_ url: URL) -> DatabaseKind? {
        guard let database = openReadOnly(url) else { return nil }
        defer { sqlite3_close(database) }

        if isCodexLogDatabase(url, database: database) {
            return .codexLog
        }

        if let role = scalarText(
            "SELECT role FROM schema_meta WHERE meta_key = 'primary' LIMIT 1",
            in: database
        ) {
            if role == "global",
               hasTables(["schema_meta", "agent_databases", "plugin_state_entries"], in: database) {
                return .openClawGlobal
            }
            if role == "agent",
               hasTables(["schema_meta", "session_nodes", "transcript_events"], in: database) {
                return .openClawAgent
            }
        }

        if hasTables(["schema_version", "sessions", "messages", "state_meta"], in: database),
           hasColumns(["id", "session_id", "role", "content", "timestamp"], table: "messages", in: database) {
            return .hermesState
        }

        if hasTables(["facts", "entities", "fact_entities", "memory_banks"], in: database),
           hasColumns(["fact_id", "content"], table: "facts", in: database) {
            return .hermesMemory
        }

        if hasTables(["tasks", "task_events", "task_comments", "task_runs"], in: database),
           hasColumns(["id", "status"], table: "tasks", in: database) {
            return .hermesKanban
        }

        if hasTables(["projects", "project_folders", "project_meta", "discovered_repos"], in: database),
           hasColumns(["id", "slug", "name"], table: "projects", in: database) {
            return .hermesProjects
        }

        if hasTables(["executions"], in: database),
           hasColumns(
            ["id", "job_id", "process_id", "status", "claimed_at"],
            table: "executions",
            in: database
           ) {
            return .hermesExecutions
        }

        if hasTables(["meta", "verification_events", "verification_state"], in: database),
           hasColumns(
            ["id", "session_id", "canonical_command", "status"],
            table: "verification_events",
            in: database
           ) {
            return .hermesVerification
        }

        if hasTables(["meta", "files", "chunks"], in: database),
           hasColumns(["path", "source", "hash"], table: "files", in: database),
           hasColumns(["id", "text", "embedding"], table: "chunks", in: database) {
            return .openClawLegacyMemory
        }

        return nil
    }

    static func isCodexLogDatabase(_ url: URL) -> Bool {
        guard let database = openReadOnly(url) else { return false }
        defer { sqlite3_close(database) }
        return isCodexLogDatabase(url, database: database)
    }

    static func sample(candidate: StorageCandidate) -> DatabaseSample? {
        var totalBytes: Int64 = 0
        var activityCounter: Int64 = 0
        var sampledAtLeastOneDatabase = false

        for target in candidate.databases {
            guard let database = openReadOnly(target.url) else { continue }
            defer { sqlite3_close(database) }

            guard classifyOpenDatabase(target.url, database: database) == target.kind else {
                continue
            }
            sampledAtLeastOneDatabase = true
            activityCounter += counter(for: target.kind, in: database)
            totalBytes += fileSetSize(for: target.url)
        }

        guard sampledAtLeastOneDatabase else { return nil }
        return DatabaseSample(
            timestamp: Date(),
            activityCounter: activityCounter,
            totalBytes: totalBytes
        )
    }

    private static func classifyOpenDatabase(
        _ url: URL,
        database: OpaquePointer
    ) -> DatabaseKind? {
        if isCodexLogDatabase(url, database: database) {
            return .codexLog
        }

        if let role = scalarText(
            "SELECT role FROM schema_meta WHERE meta_key = 'primary' LIMIT 1",
            in: database
        ) {
            if role == "global",
               hasTables(["schema_meta", "agent_databases", "plugin_state_entries"], in: database) {
                return .openClawGlobal
            }
            if role == "agent",
               hasTables(["schema_meta", "session_nodes", "transcript_events"], in: database) {
                return .openClawAgent
            }
        }

        if hasTables(["schema_version", "sessions", "messages", "state_meta"], in: database) {
            return .hermesState
        }
        if hasTables(["facts", "entities", "fact_entities", "memory_banks"], in: database) {
            return .hermesMemory
        }
        if hasTables(["tasks", "task_events", "task_comments", "task_runs"], in: database) {
            return .hermesKanban
        }
        if hasTables(["projects", "project_folders", "project_meta", "discovered_repos"], in: database) {
            return .hermesProjects
        }
        if hasTables(["executions"], in: database),
           hasColumns(["id", "job_id", "process_id", "status"], table: "executions", in: database) {
            return .hermesExecutions
        }
        if hasTables(["meta", "verification_events", "verification_state"], in: database) {
            return .hermesVerification
        }
        if hasTables(["meta", "files", "chunks"], in: database) {
            return .openClawLegacyMemory
        }
        return nil
    }

    private static func isCodexLogDatabase(
        _ url: URL,
        database: OpaquePointer
    ) -> Bool {
        guard url.lastPathComponent.range(
            of: #"^logs_[0-9]+\.sqlite$"#,
            options: .regularExpression
        ) != nil else {
            return false
        }

        return tableExists("logs", in: database)
            && hasColumns(["id", "ts"], table: "logs", in: database)
            && {
                let columns = columnNames(table: "logs", in: database)
                return columns.contains("target") || columns.contains("message")
            }()
    }

    private static func counter(for kind: DatabaseKind, in database: OpaquePointer) -> Int64 {
        let sequenceTables: [String]
        let countTables: [String]

        switch kind {
        case .codexLog:
            sequenceTables = ["logs"]
            countTables = []
        case .openClawGlobal:
            sequenceTables = ["audit_events", "session_state_events"]
            countTables = ["channel_ingress_events", "command_log_entries"]
        case .openClawAgent:
            sequenceTables = []
            countTables = [
                "transcript_events",
                "trajectory_runtime_events",
                "acp_parent_stream_events",
            ]
        case .openClawLegacyMemory:
            sequenceTables = []
            countTables = ["files", "chunks"]
        case .hermesState:
            sequenceTables = ["messages"]
            countTables = []
        case .hermesMemory:
            sequenceTables = ["facts", "entities", "memory_banks"]
            countTables = []
        case .hermesKanban:
            sequenceTables = [
                "task_events",
                "task_comments",
                "task_runs",
                "task_attachments",
            ]
            countTables = []
        case .hermesProjects:
            sequenceTables = []
            countTables = ["projects", "project_folders", "discovered_repos"]
        case .hermesExecutions:
            sequenceTables = []
            countTables = ["executions"]
        case .hermesVerification:
            sequenceTables = ["verification_events"]
            countTables = []
        }

        return sequence(in: database, tables: sequenceTables)
            + rowCounts(in: database, tables: countTables)
    }

    private static func openReadOnly(_ url: URL) -> OpaquePointer? {
        var database: OpaquePointer?
        let hasSidecars = FileManager.default.fileExists(atPath: url.path + "-wal")
            || FileManager.default.fileExists(atPath: url.path + "-shm")
        let filename = hasSidecars ? url.path : url.absoluteString + "?immutable=1"
        let flags = SQLITE_OPEN_READONLY
            | SQLITE_OPEN_FULLMUTEX
            | (hasSidecars ? 0 : SQLITE_OPEN_URI)
        guard sqlite3_open_v2(filename, &database, flags, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            return nil
        }
        sqlite3_busy_timeout(database, 250)
        return database
    }

    private static func hasTables(_ tables: [String], in database: OpaquePointer) -> Bool {
        tables.allSatisfy { tableExists($0, in: database) }
    }

    private static func tableExists(_ table: String, in database: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, table, -1, sqliteTransient)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func hasColumns(
        _ expected: Set<String>,
        table: String,
        in database: OpaquePointer
    ) -> Bool {
        columnNames(table: table, in: database).isSuperset(of: expected)
    }

    private static func columnNames(table: String, in database: OpaquePointer) -> Set<String> {
        guard table.range(of: #"^[A-Za-z0-9_]+$"#, options: .regularExpression) != nil else {
            return []
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "PRAGMA table_info(\(table))",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
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

    private static func scalarText(_ sql: String, in database: OpaquePointer) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: value)
    }

    private static func sequence(in database: OpaquePointer, tables: [String]) -> Int64 {
        guard !tables.isEmpty, tableExists("sqlite_sequence", in: database) else {
            return 0
        }

        var total: Int64 = 0
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT seq FROM sqlite_sequence WHERE name=? LIMIT 1",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(statement) }

        for table in tables {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, table, -1, sqliteTransient)
            if sqlite3_step(statement) == SQLITE_ROW {
                total += sqlite3_column_int64(statement, 0)
            }
        }
        return total
    }

    private static func rowCounts(in database: OpaquePointer, tables: [String]) -> Int64 {
        tables.reduce(0) { total, table in
            guard tableExists(table, in: database),
                  table.range(of: #"^[A-Za-z0-9_]+$"#, options: .regularExpression) != nil else {
                return total
            }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "SELECT COUNT(*) FROM \(table)",
                -1,
                &statement,
                nil
            ) == SQLITE_OK else {
                return total
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return total }
            return total + sqlite3_column_int64(statement, 0)
        }
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
