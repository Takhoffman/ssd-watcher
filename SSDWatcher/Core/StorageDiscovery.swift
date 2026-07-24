import Foundation

struct StorageDiscovery {
    func discover(customPaths: [String]) -> [StorageCandidate] {
        discover(
            customPaths: customPaths,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            includeRuntimeSources: true
        )
    }

    func discover(
        customPaths: [String],
        homeDirectory: URL,
        includeRuntimeSources: Bool
    ) -> [StorageCandidate] {
        var evidenceByLocation: [LocationKey: Set<DiscoveryEvidence>] = [:]
        var databasesByLocation: [LocationKey: Set<DatabaseTarget>] = [:]

        let explicitRoots = customPaths.map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        }

        for hint in likelyRoots(homeDirectory: homeDirectory) {
            inspect(
                root: hint.root,
                product: hint.product,
                explicit: false,
                evidenceByLocation: &evidenceByLocation,
                databasesByLocation: &databasesByLocation
            )
        }

        for root in explicitRoots {
            inspect(
                root: root,
                product: nil,
                explicit: true,
                evidenceByLocation: &evidenceByLocation,
                databasesByLocation: &databasesByLocation
            )
        }

        if includeRuntimeSources {
            for database in liveDatabasePaths() {
                register(
                    database: database,
                    extraEvidence: [.liveProcess],
                    evidenceByLocation: &evidenceByLocation,
                    databasesByLocation: &databasesByLocation
                )
            }

            for database in spotlightDatabasePaths(homeDirectory: homeDirectory) {
                register(
                    database: database,
                    extraEvidence: [],
                    evidenceByLocation: &evidenceByLocation,
                    databasesByLocation: &databasesByLocation
                )
            }
        }

        return databasesByLocation.compactMap { key, targets in
            let databases = targets.sorted {
                $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
            }
            guard !databases.isEmpty else { return nil }

            var evidence = evidenceByLocation[key, default: []]
            evidence.insert(.validatedDatabase)
            let confidence = confidenceScore(evidence: evidence)

            return StorageCandidate(
                product: key.product,
                rootURL: key.root,
                databases: databases,
                evidence: evidence,
                confidence: confidence
            )
        }
        .filter { $0.confidence >= 0.6 }
        .sorted {
            if $0.product != $1.product {
                return $0.product.displayName.localizedStandardCompare(
                    $1.product.displayName
                ) == .orderedAscending
            }
            return $0.rootURL.path.localizedStandardCompare(
                $1.rootURL.path
            ) == .orderedAscending
        }
    }

    private func likelyRoots(homeDirectory home: URL) -> [RootHint] {
        var hints: Set<RootHint> = [
            RootHint(root: home.appendingPathComponent(".codex", isDirectory: true), product: .codex),
            RootHint(root: home.appendingPathComponent(".openclaw", isDirectory: true), product: .openClaw),
            RootHint(root: home.appendingPathComponent(".clawdbot", isDirectory: true), product: .openClaw),
            RootHint(root: home.appendingPathComponent(".hermes", isDirectory: true), product: .hermes),
        ]

        guard let children = directoryChildren(of: home) else {
            return Array(hints)
        }

        for child in children {
            let name = child.lastPathComponent.lowercased()

            if name.contains("codex") || name.contains("openai") {
                addLikelyHomeOrChildren(
                    child,
                    product: .codex,
                    hints: &hints
                )
            }
            if name.contains("openclaw") || name.contains("clawdbot") {
                addLikelyHomeOrChildren(
                    child,
                    product: .openClaw,
                    hints: &hints
                )
            }
            if name.contains("hermes") {
                addLikelyHomeOrChildren(
                    child,
                    product: .hermes,
                    hints: &hints
                )
            }
        }

        let defaultHermes = home.appendingPathComponent(".hermes", isDirectory: true)
        let profiles = defaultHermes.appendingPathComponent("profiles", isDirectory: true)
        for profile in directoryChildren(of: profiles) ?? [] {
            hints.insert(RootHint(root: profile, product: .hermes))
        }

        return Array(hints)
    }

    private func addLikelyHomeOrChildren(
        _ root: URL,
        product: StorageProduct,
        hints: inout Set<RootHint>
    ) {
        let standardized = root.standardizedFileURL
        hints.insert(RootHint(root: standardized, product: product))

        guard markerEvidence(at: root, product: product).isEmpty,
              databaseFiles(at: root, product: product).isEmpty else {
            return
        }

        for child in directoryChildren(of: root) ?? [] {
            if !markerEvidence(at: child, product: product).isEmpty
                || !databaseFiles(at: child, product: product).isEmpty {
                hints.insert(RootHint(root: child, product: product))
            }
        }
    }

    private func inspect(
        root: URL,
        product: StorageProduct?,
        explicit: Bool,
        evidenceByLocation: inout [LocationKey: Set<DiscoveryEvidence>],
        databasesByLocation: inout [LocationKey: Set<DatabaseTarget>]
    ) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            return
        }

        if !isDirectory.boolValue {
            register(
                database: root,
                preferredRoot: root.deletingLastPathComponent(),
                extraEvidence: explicit ? [.explicitSelection] : [],
                evidenceByLocation: &evidenceByLocation,
                databasesByLocation: &databasesByLocation
            )
            return
        }

        let products = product.map { [$0] } ?? StorageProduct.allCases
        for candidateProduct in products {
            var evidence = markerEvidence(at: root, product: candidateProduct)
            if explicit { evidence.insert(.explicitSelection) }

            for database in databaseFiles(at: root, product: candidateProduct) {
                register(
                    database: database,
                    preferredRoot: root,
                    expectedProduct: candidateProduct,
                    extraEvidence: evidence,
                    evidenceByLocation: &evidenceByLocation,
                    databasesByLocation: &databasesByLocation
                )
            }
        }
    }

    private func databaseFiles(at root: URL, product: StorageProduct) -> [URL] {
        switch product {
        case .codex:
            return files(
                in: root,
                matching: #"^logs_[0-9]+\.sqlite$"#
            ) + files(
                in: root.appendingPathComponent("sqlite", isDirectory: true),
                matching: #"^logs_[0-9]+\.sqlite$"#
            )

        case .openClaw:
            var results = existingFiles([
                root.appendingPathComponent("state/openclaw.sqlite"),
                root.appendingPathComponent("openclaw.sqlite"),
            ])

            let agents = root.appendingPathComponent("agents", isDirectory: true)
            for agent in directoryChildren(of: agents) ?? [] {
                results += existingFiles([
                    agent.appendingPathComponent("agent/openclaw-agent.sqlite"),
                    agent.appendingPathComponent("openclaw-agent.sqlite"),
                ])
            }

            let memory = root.appendingPathComponent("memory", isDirectory: true)
            results += files(in: memory, matching: #"^.+\.sqlite$"#)
            let nestedMemory = root.appendingPathComponent(
                ".openclaw/memory",
                isDirectory: true
            )
            results += files(in: nestedMemory, matching: #"^.+\.sqlite$"#)
            return results

        case .hermes:
            var results = existingFiles([
                root.appendingPathComponent("state.db"),
                root.appendingPathComponent("memory_store.db"),
                root.appendingPathComponent("projects.db"),
                root.appendingPathComponent("verification_evidence.db"),
                root.appendingPathComponent("kanban.db"),
                root.appendingPathComponent("cron/executions.db"),
            ])

            let boards = root.appendingPathComponent("kanban/boards", isDirectory: true)
            for board in directoryChildren(of: boards) ?? [] {
                results += existingFiles([board.appendingPathComponent("kanban.db")])
            }
            return results
        }
    }

    private func register(
        database: URL,
        preferredRoot: URL? = nil,
        expectedProduct: StorageProduct? = nil,
        extraEvidence: Set<DiscoveryEvidence>,
        evidenceByLocation: inout [LocationKey: Set<DiscoveryEvidence>],
        databasesByLocation: inout [LocationKey: Set<DatabaseTarget>]
    ) {
        let standardizedDatabase = database.standardizedFileURL
        guard looksLikeSupportedDatabaseFilename(standardizedDatabase),
              let kind = DatabaseProbe.classify(standardizedDatabase),
              expectedProduct == nil || expectedProduct == kind.product else {
            return
        }

        let root = (preferredRoot ?? inferredRoot(for: standardizedDatabase, kind: kind))
            .standardizedFileURL
        let key = LocationKey(product: kind.product, root: root)
        var evidence = extraEvidence
        evidence.insert(.matchingFilename)
        evidence.formUnion(markerEvidence(at: root, product: kind.product))
        evidenceByLocation[key, default: []].formUnion(evidence)
        databasesByLocation[key, default: []].insert(
            DatabaseTarget(url: standardizedDatabase, kind: kind)
        )
    }

    private func inferredRoot(for database: URL, kind: DatabaseKind) -> URL {
        let parent = database.deletingLastPathComponent()
        switch kind {
        case .codexLog:
            return parent.lastPathComponent == "sqlite"
                ? parent.deletingLastPathComponent()
                : parent

        case .openClawGlobal:
            return parent.lastPathComponent == "state"
                ? parent.deletingLastPathComponent()
                : parent

        case .openClawAgent:
            if parent.lastPathComponent == "agent" {
                let agentDirectory = parent.deletingLastPathComponent()
                if agentDirectory.deletingLastPathComponent().lastPathComponent == "agents" {
                    return agentDirectory.deletingLastPathComponent().deletingLastPathComponent()
                }
            }
            return parent

        case .openClawLegacyMemory:
            guard parent.lastPathComponent == "memory" else { return parent }
            let stateRoot = parent.deletingLastPathComponent()
            let outerRoot = stateRoot.deletingLastPathComponent()
            if stateRoot.lastPathComponent == ".openclaw",
               FileManager.default.fileExists(
                atPath: outerRoot.appendingPathComponent("openclaw.json").path
               ) {
                return outerRoot
            }
            return stateRoot

        case .hermesExecutions:
            return parent.lastPathComponent == "cron"
                ? parent.deletingLastPathComponent()
                : parent

        case .hermesKanban:
            if parent.deletingLastPathComponent().lastPathComponent == "boards",
               parent.deletingLastPathComponent().deletingLastPathComponent()
                .lastPathComponent == "kanban" {
                return parent
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
            }
            return parent

        case .hermesState, .hermesMemory, .hermesProjects, .hermesVerification:
            return parent
        }
    }

    private func markerEvidence(
        at root: URL,
        product: StorageProduct
    ) -> Set<DiscoveryEvidence> {
        let fileManager = FileManager.default
        var evidence: Set<DiscoveryEvidence> = []

        let configurationFiles: [String]
        let sessionDirectories: [String]
        let productDirectories: [String]

        switch product {
        case .codex:
            configurationFiles = ["config.toml"]
            sessionDirectories = ["sessions"]
            productDirectories = ["skills", "rules"]
        case .openClaw:
            configurationFiles = ["openclaw.json", "clawdbot.json"]
            sessionDirectories = ["agents"]
            productDirectories = ["state", "credentials", "memory"]
        case .hermes:
            configurationFiles = ["config.yaml"]
            sessionDirectories = ["sessions"]
            productDirectories = ["skills", "plugins", "cron", "kanban"]
        }

        if configurationFiles.contains(where: {
            fileManager.fileExists(atPath: root.appendingPathComponent($0).path)
        }) {
            evidence.insert(.configuration)
        }

        if sessionDirectories.contains(where: {
            isDirectory(root.appendingPathComponent($0, isDirectory: true))
        }) {
            evidence.insert(.sessions)
        }

        if productDirectories.contains(where: {
            isDirectory(root.appendingPathComponent($0, isDirectory: true))
        }) {
            evidence.insert(.productFiles)
        }

        return evidence
    }

    private func liveDatabasePaths() -> [URL] {
        let output = run(
            executable: "/usr/sbin/lsof",
            arguments: [
                "-n", "-P",
                "-c", "codex",
                "-c", "openclaw",
                "-c", "hermes",
                "-c", "node",
                "-c", "python",
                "-c", "python3",
                "-Fn",
            ]
        )

        return Array(Set(output.split(separator: "\n").compactMap { line -> URL? in
            guard line.first == "n" else { return nil }
            var path = String(line.dropFirst())
            path = path.replacingOccurrences(
                of: #"-(wal|shm)$"#,
                with: "",
                options: .regularExpression
            )
            let url = URL(fileURLWithPath: path)
            return looksLikeSupportedDatabaseFilename(url) ? url : nil
        }))
    }

    private func spotlightDatabasePaths(homeDirectory: URL) -> [URL] {
        let query = [
            #"kMDItemFSName == "logs_*.sqlite"cd"#,
            #"kMDItemFSName == "openclaw.sqlite"cd"#,
            #"kMDItemFSName == "openclaw-agent.sqlite"cd"#,
            #"kMDItemFSName == "state.db"cd"#,
            #"kMDItemFSName == "memory_store.db"cd"#,
            #"kMDItemFSName == "projects.db"cd"#,
            #"kMDItemFSName == "kanban.db"cd"#,
            #"kMDItemFSName == "executions.db"cd"#,
            #"kMDItemFSName == "verification_evidence.db"cd"#,
        ]
        .map { "(\($0))" }
        .joined(separator: " || ")

        return spotlightSearchRoots(homeDirectory: homeDirectory).flatMap { searchRoot in
            run(
                executable: "/usr/bin/mdfind",
                arguments: ["-onlyin", searchRoot.path, query]
            )
            .split(separator: "\n")
            .prefix(500)
            .map { URL(fileURLWithPath: String($0)) }
        }
    }

    private func spotlightSearchRoots(homeDirectory: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [
            .volumeIsBrowsableKey,
            .volumeIsInternalKey,
            .volumeIsLocalKey,
        ]
        let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) ?? []

        let externalLocalVolumes = mountedVolumes.filter { volume in
            guard volume.path != "/" else { return false }
            guard let values = try? volume.resourceValues(forKeys: keys) else { return false }
            return values.volumeIsBrowsable != false
                && values.volumeIsLocal != false
                && values.volumeIsInternal != true
        }

        return [homeDirectory] + externalLocalVolumes
    }

    private func looksLikeSupportedDatabaseFilename(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        if name.range(
            of: #"^logs_[0-9]+\.sqlite$"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        let knownNames: Set<String> = [
            "openclaw.sqlite",
            "openclaw-agent.sqlite",
            "state.db",
            "memory_store.db",
            "projects.db",
            "kanban.db",
            "executions.db",
            "verification_evidence.db",
        ]
        if knownNames.contains(name) {
            return true
        }

        return name.hasSuffix(".sqlite")
            && url.deletingLastPathComponent().lastPathComponent == "memory"
    }

    private func files(in directory: URL, matching pattern: String) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        return files.filter {
            $0.lastPathComponent.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func existingFiles(_ urls: [URL]) -> [URL] {
        urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func directoryChildren(of directory: URL) -> [URL]? {
        try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        .filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func run(executable: String, arguments: [String]) -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return ""
        }
    }

    private func confidenceScore(evidence: Set<DiscoveryEvidence>) -> Double {
        var score = 0.0
        if evidence.contains(.validatedDatabase) { score += 0.55 }
        if evidence.contains(.liveProcess) { score += 0.25 }
        if evidence.contains(.configuration) { score += 0.12 }
        if evidence.contains(.sessions) { score += 0.12 }
        if evidence.contains(.productFiles) { score += 0.06 }
        if evidence.contains(.matchingFilename) { score += 0.08 }
        if evidence.contains(.explicitSelection) { score += 0.25 }
        return min(score, 1)
    }
}

private struct RootHint: Hashable {
    let root: URL
    let product: StorageProduct
}

private struct LocationKey: Hashable {
    let product: StorageProduct
    let root: URL
}
