import Foundation

enum CodexProviderConfigError: Error, Equatable, LocalizedError {
    case invalidProviderID
    case invalidBaseURL
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidProviderID:
            return L10n.text("relay.error.invalid_provider_id")
        case .invalidBaseURL:
            return L10n.text("relay.error.invalid_base_url")
        case let .writeFailed(message):
            return L10n.text("relay.error.config_write_failed_format", message)
        }
    }
}

struct CodexProviderConfig: Equatable {
    nonisolated static let relayHistoryBucketProviderID = "custom"

    let providerID: String
    let name: String
    let baseURL: URL
    let wireAPI: String
    let requiresOpenAIAuth: Bool

    init(
        providerID: String,
        name: String,
        baseURL: String,
        wireAPI: String = AgentAccount.defaultRelayWireAPI,
        requiresOpenAIAuth: Bool = true
    ) throws {
        let trimmedProviderID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedProviderID.range(of: #"^[A-Za-z0-9_]+$"#, options: .regularExpression) != nil else {
            throw CodexProviderConfigError.invalidProviderID
        }
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedBaseURL = URL(string: trimmedBaseURL),
              parsedBaseURL.scheme?.hasPrefix("http") == true,
              parsedBaseURL.host?.isEmpty == false
        else {
            throw CodexProviderConfigError.invalidBaseURL
        }

        self.providerID = trimmedProviderID
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmedName.isEmpty ? trimmedProviderID : trimmedName
        self.baseURL = parsedBaseURL
        let trimmedWireAPI = wireAPI.trimmingCharacters(in: .whitespacesAndNewlines)
        self.wireAPI = trimmedWireAPI.isEmpty ? AgentAccount.defaultRelayWireAPI : trimmedWireAPI
        self.requiresOpenAIAuth = requiresOpenAIAuth
    }

    func renderTOMLBlock(providerID overrideProviderID: String? = nil, apiKey: String? = nil) -> String {
        let tableProviderID = overrideProviderID ?? providerID
        var lines = [
            "[model_providers.\(tableProviderID)]",
            "name = \"\(Self.escape(name))\"",
            "base_url = \"\(Self.escape(baseURL.absoluteString))\"",
            "wire_api = \"\(Self.escape(wireAPI))\"",
            "requires_openai_auth = \(requiresOpenAIAuth ? "true" : "false")"
        ]
        if let trimmedAPIKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedAPIKey.isEmpty
        {
            lines.append("experimental_bearer_token = \"\(Self.escape(trimmedAPIKey))\"")
        }
        return lines.joined(separator: "\n")
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum CodexProviderConfigMerger {
    static func merge(existing: String, provider: CodexProviderConfig) -> String {
        merge(existing: existing, provider: provider, apiKey: nil)
    }

    static func mergePreservingOfficialAuth(
        existing: String,
        provider: CodexProviderConfig,
        apiKey: String
    ) -> String {
        merge(
            existing: existing,
            provider: provider,
            modelProviderID: CodexProviderConfig.relayHistoryBucketProviderID,
            apiKey: apiKey
        )
    }

    private static func merge(
        existing: String,
        provider: CodexProviderConfig,
        modelProviderID: String? = nil,
        apiKey: String?
    ) -> String {
        let activeProviderID = modelProviderID ?? provider.providerID
        var lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        replaceTopLevelModelProvider(in: &lines, providerID: activeProviderID)
        let providerIDsToReplace = Set([provider.providerID, activeProviderID])
        for providerID in providerIDsToReplace {
            removeProviderTable(providerID, from: &lines)
        }
        trimTrailingBlankLines(&lines)
        if !lines.isEmpty {
            lines.append("")
        }
        lines.append(provider.renderTOMLBlock(providerID: activeProviderID, apiKey: apiKey))
        return lines.joined(separator: "\n") + "\n"
    }

    static func resetModelProvider(existing: String) -> String {
        var lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let activeProviderID = topLevelModelProviderID(in: lines)
        removeTopLevelExperimentalBearerToken(from: &lines)
        if let activeProviderID {
            removeExperimentalBearerToken(providerID: activeProviderID, from: &lines)
        }
        removeTopLevelModelProvider(from: &lines)
        trimTrailingBlankLines(&lines)
        guard !lines.isEmpty else { return "" }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func replaceTopLevelModelProvider(in lines: inout [String], providerID: String) {
        var insideTable = false
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                insideTable = true
            }
            if !insideTable && isModelProviderAssignment(trimmed) {
                lines[index] = "model_provider = \"\(providerID)\""
                return
            }
        }
        lines.insert("model_provider = \"\(providerID)\"", at: 0)
    }

    private static func removeTopLevelModelProvider(from lines: inout [String]) {
        var insideTable = false
        var indexesToRemove: [Int] = []
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                insideTable = true
            }
            if !insideTable && isModelProviderAssignment(trimmed) {
                indexesToRemove.append(index)
            }
        }

        for index in indexesToRemove.reversed() {
            lines.remove(at: index)
        }
    }

    private static func topLevelModelProviderID(in lines: [String]) -> String? {
        var insideTable = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                insideTable = true
            }
            if !insideTable, isModelProviderAssignment(trimmed) {
                return stringAssignmentValue(from: trimmed)
            }
        }
        return nil
    }

    private static func removeTopLevelExperimentalBearerToken(from lines: inout [String]) {
        var insideTable = false
        var indexesToRemove: [Int] = []
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                insideTable = true
            }
            if !insideTable && isExperimentalBearerTokenAssignment(trimmed) {
                indexesToRemove.append(index)
            }
        }

        for index in indexesToRemove.reversed() {
            lines.remove(at: index)
        }
    }

    private static func removeExperimentalBearerToken(providerID: String, from lines: inout [String]) {
        let header = "[model_providers.\(providerID)]"
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) else {
            return
        }

        var indexesToRemove: [Int] = []
        var index = lines.index(after: start)
        while index < lines.endIndex {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                break
            }
            if isExperimentalBearerTokenAssignment(trimmed) {
                indexesToRemove.append(index)
            }
            index = lines.index(after: index)
        }

        for index in indexesToRemove.reversed() {
            lines.remove(at: index)
        }
    }

    private static func removeProviderTable(_ providerID: String, from lines: inout [String]) {
        let header = "[model_providers.\(providerID)]"
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) else {
            return
        }

        var end = lines.index(after: start)
        while end < lines.endIndex {
            let trimmed = lines[end].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                break
            }
            end = lines.index(after: end)
        }
        lines.removeSubrange(start..<end)
    }

    private static func trimTrailingBlankLines(_ lines: inout [String]) {
        while lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeLast()
        }
    }

    private static func isModelProviderAssignment(_ trimmedLine: String) -> Bool {
        trimmedLine.range(of: "^model_provider\\s*=", options: .regularExpression) != nil
    }

    private static func isExperimentalBearerTokenAssignment(_ trimmedLine: String) -> Bool {
        trimmedLine.range(of: "^experimental_bearer_token\\s*=", options: .regularExpression) != nil
    }

    private static func stringAssignmentValue(from trimmedLine: String) -> String? {
        guard let equalsIndex = trimmedLine.firstIndex(of: "=") else { return nil }
        let rawValue = trimmedLine[trimmedLine.index(after: equalsIndex)...]
            .trimmingCharacters(in: .whitespaces)
        guard let quote = rawValue.first, quote == "\"" || quote == "'" else { return nil }
        let valueStart = rawValue.index(after: rawValue.startIndex)
        guard let valueEnd = rawValue[valueStart...].firstIndex(of: quote) else { return nil }
        return String(rawValue[valueStart..<valueEnd])
    }
}

struct CodexProviderConfigService {
    var configURLProvider: () -> URL = {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/config.toml")
    }

    func apply(_ provider: CodexProviderConfig) throws {
        let url = configURLProvider()
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let merged = CodexProviderConfigMerger.merge(existing: existing, provider: provider)

        try write(merged, to: url)
    }

    func applyPreservingOfficialAuth(_ provider: CodexProviderConfig, apiKey: String) throws {
        let url = configURLProvider()
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let merged = CodexProviderConfigMerger.mergePreservingOfficialAuth(
            existing: existing,
            provider: provider,
            apiKey: apiKey
        )

        try write(merged, to: url)
    }

    private func write(_ contents: String, to url: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw CodexProviderConfigError.writeFailed(error.localizedDescription)
        }
    }

    func resetToDefaultModelProvider() throws {
        let url = configURLProvider()
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let existing: String
        do {
            existing = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw CodexProviderConfigError.writeFailed(error.localizedDescription)
        }

        let reset = CodexProviderConfigMerger.resetModelProvider(existing: existing)
        guard reset != existing else { return }

        do {
            try reset.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw CodexProviderConfigError.writeFailed(error.localizedDescription)
        }
    }
}

struct CodexRelayHistoryBucketMigrationOutcome: Equatable {
    var migratedSessionFiles: Int
    var migratedThreadRows: Int

    var didMigrate: Bool {
        migratedSessionFiles > 0 || migratedThreadRows > 0
    }
}

struct CodexRelayHistoryBucketMigrationService {
    typealias SQLiteRunner = (_ databaseURL: URL, _ command: String) throws -> String

    var codexDirectoryProvider: () -> URL = {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex", directoryHint: .isDirectory)
    }
    var backupDirectoryProvider: (_ codexDirectory: URL) -> URL = { codexDirectory in
        let stamp = CodexRelayHistoryBucketMigrationService.backupTimestamp()
        return codexDirectory
            .appending(path: "codex-pool-manager-backups", directoryHint: .isDirectory)
            .appending(path: "relay-history-bucket-\(stamp)", directoryHint: .isDirectory)
    }
    var sqliteRunner: SQLiteRunner = Self.defaultSQLiteRunner

    func migrate(sourceProviderID: String) throws -> CodexRelayHistoryBucketMigrationOutcome {
        try migrate(sourceProviderIDs: [sourceProviderID])
    }

    func migrate(sourceProviderIDs: Set<String>) throws -> CodexRelayHistoryBucketMigrationOutcome {
        let sourceProviderIDs = Self.normalizedSourceProviderIDs(sourceProviderIDs)
        guard !sourceProviderIDs.isEmpty else {
            return CodexRelayHistoryBucketMigrationOutcome(migratedSessionFiles: 0, migratedThreadRows: 0)
        }

        let codexDirectory = codexDirectoryProvider()
        let backupDirectory = backupDirectoryProvider(codexDirectory)
        let migratedSessionFiles = try migrateJSONLSessions(
            codexDirectory: codexDirectory,
            backupDirectory: backupDirectory,
            sourceProviderIDs: sourceProviderIDs
        )
        let migratedThreadRows = try migrateStateDatabase(
            codexDirectory: codexDirectory,
            backupDirectory: backupDirectory,
            sourceProviderIDs: sourceProviderIDs
        )
        return CodexRelayHistoryBucketMigrationOutcome(
            migratedSessionFiles: migratedSessionFiles,
            migratedThreadRows: migratedThreadRows
        )
    }

    private func migrateJSONLSessions(
        codexDirectory: URL,
        backupDirectory: URL,
        sourceProviderIDs: Set<String>
    ) throws -> Int {
        let roots = [
            codexDirectory.appending(path: "sessions", directoryHint: .isDirectory),
            codexDirectory.appending(path: "archived_sessions", directoryHint: .isDirectory)
        ]
        var migratedFiles = 0
        for root in roots {
            for fileURL in jsonlFiles(in: root) {
                if try rewriteSessionFileIfNeeded(
                    fileURL,
                    codexDirectory: codexDirectory,
                    backupDirectory: backupDirectory,
                    sourceProviderIDs: sourceProviderIDs
                ) {
                    migratedFiles += 1
                }
            }
        }
        return migratedFiles
    }

    private func jsonlFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
            return url
        }
    }

    private func rewriteSessionFileIfNeeded(
        _ fileURL: URL,
        codexDirectory: URL,
        backupDirectory: URL,
        sourceProviderIDs: Set<String>
    ) throws -> Bool {
        let fingerprint = try fileFingerprint(fileURL)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        var rewritten = ""
        rewritten.reserveCapacity(content.count)
        var didChange = false

        let segments = content.split(separator: "\n", omittingEmptySubsequences: false)
        for (offset, segment) in segments.enumerated() {
            let line = String(segment)
            if let nextLine = Self.rewriteSessionMetaLine(line, sourceProviderIDs: sourceProviderIDs) {
                rewritten += nextLine
                didChange = true
            } else {
                rewritten += line
            }
            if offset < segments.count - 1 {
                rewritten += "\n"
            }
        }

        guard didChange else { return false }

        try ensureFileUnchanged(fileURL, fingerprint: fingerprint)
        try backupFile(fileURL, codexDirectory: codexDirectory, backupDirectory: backupDirectory, category: "jsonl")
        try ensureFileUnchanged(fileURL, fingerprint: fingerprint)
        try rewritten.write(to: fileURL, atomically: true, encoding: .utf8)
        return true
    }

    nonisolated private static func rewriteSessionMetaLine(
        _ line: String,
        sourceProviderIDs: Set<String>
    ) -> String? {
        guard line.contains("\"session_meta\""), line.contains("\"model_provider\"") else {
            return nil
        }
        guard let data = line.data(using: .utf8),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["type"] as? String == "session_meta",
              var payload = root["payload"] as? [String: Any],
              let modelProvider = payload["model_provider"] as? String,
              sourceProviderIDs.contains(modelProvider)
        else {
            return nil
        }

        payload["model_provider"] = CodexProviderConfig.relayHistoryBucketProviderID
        root["payload"] = payload
        guard let output = try? JSONSerialization.data(withJSONObject: root),
              let rewritten = String(data: output, encoding: .utf8)
        else {
            return nil
        }
        return rewritten
    }

    private func migrateStateDatabase(
        codexDirectory: URL,
        backupDirectory: URL,
        sourceProviderIDs: Set<String>
    ) throws -> Int {
        let databaseURL = codexDirectory.appending(path: "state_5.sqlite")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return 0 }
        guard try sqliteScalar(databaseURL, "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='threads';") != "0",
              try sqliteScalar(databaseURL, "SELECT COUNT(*) FROM pragma_table_info('threads') WHERE name='model_provider';") != "0"
        else {
            return 0
        }

        let quotedSourceIDs = sourceProviderIDs
            .sorted()
            .map(Self.sqliteStringLiteral)
            .joined(separator: ", ")
        let count = Int(try sqliteScalar(
            databaseURL,
            "SELECT COUNT(*) FROM threads WHERE model_provider IN (\(quotedSourceIDs));"
        )) ?? 0
        guard count > 0 else { return 0 }

        try backupStateDatabase(databaseURL, codexDirectory: codexDirectory, backupDirectory: backupDirectory)
        let target = Self.sqliteStringLiteral(CodexProviderConfig.relayHistoryBucketProviderID)
        _ = try sqliteRunner(
            databaseURL,
            "UPDATE threads SET model_provider = \(target) WHERE model_provider IN (\(quotedSourceIDs));"
        )
        return count
    }

    private func sqliteScalar(_ databaseURL: URL, _ command: String) throws -> String {
        try sqliteRunner(databaseURL, command)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func backupStateDatabase(
        _ databaseURL: URL,
        codexDirectory: URL,
        backupDirectory: URL
    ) throws {
        let backupURL = backupDirectory
            .appending(path: "state", directoryHint: .isDirectory)
            .appending(path: relativePath(for: databaseURL, from: codexDirectory))
        try FileManager.default.createDirectory(
            at: backupURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = try sqliteRunner(databaseURL, ".backup \(Self.sqliteStringLiteral(backupURL.path))")
    }

    private func backupFile(
        _ fileURL: URL,
        codexDirectory: URL,
        backupDirectory: URL,
        category: String
    ) throws {
        let backupURL = backupDirectory
            .appending(path: category, directoryHint: .isDirectory)
            .appending(path: relativePath(for: fileURL, from: codexDirectory))
        try FileManager.default.createDirectory(
            at: backupURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
        try FileManager.default.copyItem(at: fileURL, to: backupURL)
    }

    private func relativePath(for fileURL: URL, from directoryURL: URL) -> String {
        let basePath = directoryURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        if filePath == basePath {
            return fileURL.lastPathComponent
        }
        if filePath.hasPrefix(basePath + "/") {
            return String(filePath.dropFirst(basePath.count + 1))
        }
        return fileURL.lastPathComponent
    }

    private func fileFingerprint(_ fileURL: URL) throws -> (modified: Date?, size: UInt64?) {
        let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return (values.contentModificationDate, values.fileSize.map(UInt64.init))
    }

    private func ensureFileUnchanged(
        _ fileURL: URL,
        fingerprint: (modified: Date?, size: UInt64?)
    ) throws {
        let current = try fileFingerprint(fileURL)
        guard current.modified == fingerprint.modified, current.size == fingerprint.size else {
            throw CodexProviderConfigError.writeFailed("Codex session file changed during migration: \(fileURL.path)")
        }
    }

    nonisolated private static func normalizedSourceProviderIDs(_ values: Set<String>) -> Set<String> {
        Set(values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed != CodexProviderConfig.relayHistoryBucketProviderID,
                  trimmed != "openai"
            else {
                return nil
            }
            return trimmed
        })
    }

    nonisolated private static func defaultSQLiteRunner(databaseURL: URL, command: String) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [databaseURL.path, command]
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        process.waitUntilExit()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw CodexProviderConfigError.writeFailed(output)
        }
        return output
    }

    nonisolated private static func sqliteStringLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    nonisolated private static func backupTimestamp(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
