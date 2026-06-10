import Foundation

enum CodexAPIKeyLoginError: Error, LocalizedError, Equatable {
    case loginFailed(String, diagnosticLog: String? = nil)

    var errorDescription: String? {
        switch self {
        case let .loginFailed(message, _):
            return L10n.text("relay.error.login_failed_format", message)
        }
    }

    var diagnosticLog: String? {
        switch self {
        case let .loginFailed(_, diagnosticLog):
            diagnosticLog
        }
    }

    static func == (lhs: CodexAPIKeyLoginError, rhs: CodexAPIKeyLoginError) -> Bool {
        switch (lhs, rhs) {
        case let (.loginFailed(lhsMessage, _), .loginFailed(rhsMessage, _)):
            lhsMessage == rhsMessage
        }
    }
}

struct CodexAPIKeyLoginService {
    var authFileURLProvider: () -> URL = {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/auth.json")
    }

    @discardableResult
    func login(apiKey: String) async throws -> String {
        let trimmed = Self.trimmedStableCopy(apiKey)
        return try await login(trimmedAPIKeyData: Data(Array(trimmed.utf8)))
    }

    @discardableResult
    func login(trimmedAPIKeyData apiKeyData: Data) async throws -> String {
        let authURL = authFileURLProvider()
        let trimmedAPIKey = Self.trimmedAPIKey(from: apiKeyData)
        guard !trimmedAPIKey.isEmpty else {
            let diagnosticLog = Self.diagnosticLog(
                stage: "missing_api_key",
                apiKeyDataLength: apiKeyData.count,
                trimmedAPIKeyLength: trimmedAPIKey.count,
                authURL: authURL,
                authFileExistsAfter: nil
            )
            throw CodexAPIKeyLoginError.loginFailed(
                L10n.text("relay.error.missing_api_key"),
                diagnosticLog: diagnosticLog
            )
        }

        let authData: Data
        do {
            authData = try Self.apiKeyAuthData(apiKey: trimmedAPIKey)
            try FileManager.default.createDirectory(
                at: authURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try authData.write(to: authURL, options: [.atomic])
            return Self.diagnosticLog(
                stage: "written",
                apiKeyDataLength: apiKeyData.count,
                trimmedAPIKeyLength: trimmedAPIKey.count,
                authURL: authURL,
                authFileExistsAfter: FileManager.default.fileExists(atPath: authURL.path)
            )
        } catch {
            let diagnosticLog = Self.diagnosticLog(
                stage: "write_failed",
                apiKeyDataLength: apiKeyData.count,
                trimmedAPIKeyLength: trimmedAPIKey.count,
                authURL: authURL,
                authFileExistsAfter: FileManager.default.fileExists(atPath: authURL.path),
                errorDescription: error.localizedDescription
            )
            throw CodexAPIKeyLoginError.loginFailed(error.localizedDescription, diagnosticLog: diagnosticLog)
        }
    }

    private static func trimmedStableCopy(_ value: String) -> String {
        String(decoding: Array(value.utf8), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimmedAPIKey(from apiKeyData: Data) -> String {
        String(decoding: Array(apiKeyData), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func apiKeyAuthData(apiKey: String) throws -> Data {
        let payload: [String: Any] = [
            "auth_mode": "apikey",
            "OPENAI_API_KEY": apiKey
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private static func diagnosticLog(
        stage: String,
        apiKeyDataLength: Int,
        trimmedAPIKeyLength: Int,
        authURL: URL,
        authFileExistsAfter: Bool?,
        errorDescription: String? = nil
    ) -> String {
        let fileManager = FileManager.default
        let directoryURL = authURL.deletingLastPathComponent()
        return [
            "Relay API key auth diagnostic:",
            "auth_write_stage=\(stage)",
            "api_key_data_len=\(apiKeyDataLength)",
            "trimmed_api_key_len=\(trimmedAPIKeyLength)",
            "auth_file_path=\(displayPath(authURL))",
            "auth_dir_exists_before=\(fileManager.fileExists(atPath: directoryURL.path))",
            "auth_file_exists_before=\(fileManager.fileExists(atPath: authURL.path))",
            "auth_file_exists_after=\(value(authFileExistsAfter))",
            "error_description=\(value(errorDescription))"
        ].joined(separator: "\n")
    }

    private static func displayPath(_ url: URL) -> String {
        let path = url.path
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if path == homePath {
            return "~"
        }
        if path.hasPrefix(homePath + "/") {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }

    private static func value(_ value: Bool?) -> String {
        value.map { $0 ? "true" : "false" } ?? "nil"
    }

    private static func value(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "nil" }
        return value.replacingOccurrences(of: "\n", with: "\\n")
    }
}
