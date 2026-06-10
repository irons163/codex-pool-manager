import Foundation

enum CodexAPIKeyLoginError: Error, LocalizedError, Equatable {
    case loginFailed(String)

    var errorDescription: String? {
        switch self {
        case let .loginFailed(message):
            return L10n.text("relay.error.login_failed_format", message)
        }
    }
}

struct CodexAPIKeyLoginService {
    var authFileURLProvider: () -> URL = {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/auth.json")
    }

    func login(apiKey: String) async throws {
        let trimmed = Self.trimmedStableCopy(apiKey)
        try await login(trimmedAPIKeyData: Data(Array(trimmed.utf8)))
    }

    func login(trimmedAPIKeyData apiKeyData: Data) async throws {
        let apiKey = try Self.trimmedAPIKey(from: apiKeyData)
        let authURL = authFileURLProvider()
        let authData: Data
        do {
            authData = try Self.apiKeyAuthData(apiKey: apiKey)
            try FileManager.default.createDirectory(
                at: authURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try authData.write(to: authURL, options: [.atomic])
        } catch {
            throw CodexAPIKeyLoginError.loginFailed(error.localizedDescription)
        }
    }

    private static func trimmedStableCopy(_ value: String) -> String {
        String(decoding: Array(value.utf8), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimmedAPIKey(from apiKeyData: Data) throws -> String {
        let trimmedAPIKey = String(decoding: Array(apiKeyData), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            throw CodexAPIKeyLoginError.loginFailed(L10n.text("relay.error.missing_api_key"))
        }

        return trimmedAPIKey
    }

    private static func apiKeyAuthData(apiKey: String) throws -> Data {
        let payload: [String: Any] = [
            "auth_mode": "apikey",
            "OPENAI_API_KEY": apiKey
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }
}
