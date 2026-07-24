import Foundation

struct CodexHomeDiscovery {
    func discover(customPaths: [String]) -> [HomeCandidate] {
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
    ) -> [HomeCandidate] {
        var evidenceByRoot: [URL: Set<DiscoveryEvidence>] = [:]
        var databasesByRoot: [URL: Set<URL>] = [:]

        let explicitRoots = customPaths.map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        }

        for root in likelyRoots(homeDirectory: homeDirectory) + explicitRoots {
            inspect(
                root: root,
                explicit: explicitRoots.contains(root),
                evidenceByRoot: &evidenceByRoot,
                databasesByRoot: &databasesByRoot
            )
        }

        if includeRuntimeSources {
            for database in liveCodexDatabasePaths() {
                register(
                    database: database,
                    extraEvidence: [.liveCodexProcess],
                    evidenceByRoot: &evidenceByRoot,
                    databasesByRoot: &databasesByRoot
                )
            }

            for database in spotlightDatabasePaths(homeDirectory: homeDirectory) {
                register(
                    database: database,
                    extraEvidence: [],
                    evidenceByRoot: &evidenceByRoot,
                    databasesByRoot: &databasesByRoot
                )
            }
        }

        return databasesByRoot.compactMap { root, databaseSet in
            let validDatabases = databaseSet
                .filter(DatabaseProbe.isCodexLogDatabase)
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            guard !validDatabases.isEmpty else { return nil }

            var evidence = evidenceByRoot[root, default: []]
            evidence.insert(.validatedDatabase)
            let confidence = confidenceScore(evidence: evidence)

            return HomeCandidate(
                rootURL: root,
                databaseURLs: validDatabases,
                evidence: evidence,
                confidence: confidence
            )
        }
        .filter { $0.confidence >= 0.6 }
        .sorted { $0.rootURL.path.localizedStandardCompare($1.rootURL.path) == .orderedAscending }
    }

    private func likelyRoots(homeDirectory home: URL) -> [URL] {
        let fileManager = FileManager.default
        var roots: Set<URL> = [home.appendingPathComponent(".codex", isDirectory: true)]

        guard let children = try? fileManager.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return Array(roots)
        }

        for child in children {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }

            let name = child.lastPathComponent.lowercased()
            if name.contains("codex") || name.contains("openai") {
                roots.insert(child.standardizedFileURL)

                let childAlreadyLooksLikeHome = !markerEvidence(at: child).isEmpty
                    || !databaseFiles(in: child).isEmpty

                if !childAlreadyLooksLikeHome,
                   let grandchildren = try? fileManager.contentsOfDirectory(
                    at: child,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: []
                ) {
                    for grandchild in grandchildren {
                        let grandchildValues = try? grandchild.resourceValues(forKeys: [.isDirectoryKey])
                        guard grandchildValues?.isDirectory == true else { continue }

                        let grandchildLooksLikeHome = !markerEvidence(at: grandchild).isEmpty
                            || !databaseFiles(in: grandchild).isEmpty
                            || !databaseFiles(
                                in: grandchild.appendingPathComponent("sqlite", isDirectory: true)
                            ).isEmpty

                        if grandchildLooksLikeHome {
                            roots.insert(grandchild.standardizedFileURL)
                        }
                    }
                }
            }
        }

        return Array(roots)
    }

    private func inspect(
        root: URL,
        explicit: Bool,
        evidenceByRoot: inout [URL: Set<DiscoveryEvidence>],
        databasesByRoot: inout [URL: Set<URL>]
    ) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else { return }

        var evidence = markerEvidence(at: root)
        if explicit { evidence.insert(.explicitSelection) }
        evidenceByRoot[root, default: []].formUnion(evidence)

        let directDatabases = databaseFiles(in: root)
        for database in directDatabases {
            register(
                database: database,
                preferredRoot: root,
                extraEvidence: evidence,
                evidenceByRoot: &evidenceByRoot,
                databasesByRoot: &databasesByRoot
            )
        }

        let legacySQLite = root.appendingPathComponent("sqlite", isDirectory: true)
        for database in databaseFiles(in: legacySQLite) {
            register(
                database: database,
                preferredRoot: root,
                extraEvidence: evidence,
                evidenceByRoot: &evidenceByRoot,
                databasesByRoot: &databasesByRoot
            )
        }
    }

    private func databaseFiles(in directory: URL) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        return files.filter {
            $0.lastPathComponent.range(
                of: #"^logs_[0-9]+\.sqlite$"#,
                options: .regularExpression
            ) != nil
        }
    }

    private func register(
        database: URL,
        preferredRoot: URL? = nil,
        extraEvidence: Set<DiscoveryEvidence>,
        evidenceByRoot: inout [URL: Set<DiscoveryEvidence>],
        databasesByRoot: inout [URL: Set<URL>]
    ) {
        let standardizedDatabase = database.standardizedFileURL
        guard standardizedDatabase.lastPathComponent.range(
            of: #"^logs_[0-9]+\.sqlite$"#,
            options: .regularExpression
        ) != nil else {
            return
        }

        let root = preferredRoot ?? inferredRoot(for: standardizedDatabase)
        var evidence = extraEvidence
        evidence.insert(.matchingFilename)
        evidence.formUnion(markerEvidence(at: root))
        evidenceByRoot[root, default: []].formUnion(evidence)
        databasesByRoot[root, default: []].insert(standardizedDatabase)
    }

    private func inferredRoot(for database: URL) -> URL {
        let parent = database.deletingLastPathComponent()
        if parent.lastPathComponent == "sqlite" {
            return parent.deletingLastPathComponent().standardizedFileURL
        }
        return parent.standardizedFileURL
    }

    private func markerEvidence(at root: URL) -> Set<DiscoveryEvidence> {
        let fileManager = FileManager.default
        var evidence: Set<DiscoveryEvidence> = []

        if fileManager.fileExists(atPath: root.appendingPathComponent("config.toml").path) {
            evidence.insert(.configuration)
        }

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(
            atPath: root.appendingPathComponent("sessions").path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue {
            evidence.insert(.sessions)
        }

        for directory in ["skills", "rules"] {
            isDirectory = false
            if fileManager.fileExists(
                atPath: root.appendingPathComponent(directory).path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue {
                evidence.insert(.skillsOrRules)
                break
            }
        }

        return evidence
    }

    private func liveCodexDatabasePaths() -> [URL] {
        run(
            executable: "/usr/sbin/lsof",
            arguments: ["-n", "-P", "-c", "codex", "-Fn"]
        )
        .split(separator: "\n")
        .compactMap { line -> URL? in
            guard line.first == "n" else { return nil }
            let path = String(line.dropFirst())
            let databasePath = path
                .replacingOccurrences(of: "-wal", with: "")
                .replacingOccurrences(of: "-shm", with: "")
            guard databasePath.range(
                of: #"/logs_[0-9]+\.sqlite$"#,
                options: .regularExpression
            ) != nil else {
                return nil
            }
            return URL(fileURLWithPath: databasePath)
        }
    }

    private func spotlightDatabasePaths(homeDirectory: URL) -> [URL] {
        spotlightSearchRoots(homeDirectory: homeDirectory).flatMap { searchRoot in
            run(
                executable: "/usr/bin/mdfind",
                arguments: [
                    "-onlyin",
                    searchRoot.path,
                    #"kMDItemFSName == "logs_*.sqlite"cd"#,
                ]
            )
            .split(separator: "\n")
            .prefix(250)
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
        if evidence.contains(.liveCodexProcess) { score += 0.25 }
        if evidence.contains(.configuration) { score += 0.12 }
        if evidence.contains(.sessions) { score += 0.12 }
        if evidence.contains(.skillsOrRules) { score += 0.06 }
        if evidence.contains(.matchingFilename) { score += 0.08 }
        if evidence.contains(.explicitSelection) { score += 0.25 }
        return min(score, 1)
    }
}
