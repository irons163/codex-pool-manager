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

    func renderTOMLBlock() -> String {
        """
        [model_providers.\(providerID)]
        name = \"\(Self.escape(name))\"
        base_url = \"\(Self.escape(baseURL.absoluteString))\"
        wire_api = \"\(Self.escape(wireAPI))\"
        requires_openai_auth = \(requiresOpenAIAuth ? "true" : "false")
        """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum CodexProviderConfigMerger {
    static func merge(existing: String, provider: CodexProviderConfig) -> String {
        var lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        replaceTopLevelModelProvider(in: &lines, providerID: provider.providerID)
        removeProviderTable(provider.providerID, from: &lines)
        trimTrailingBlankLines(&lines)
        if !lines.isEmpty {
            lines.append("")
        }
        lines.append(provider.renderTOMLBlock())
        return lines.joined(separator: "\n") + "\n"
    }

    static func resetModelProvider(existing: String) -> String {
        var lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
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
        trimmedLine.range(of: #"^model_provider\s*="#, options: .regularExpression) != nil
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

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try merged.write(to: url, atomically: true, encoding: .utf8)
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
