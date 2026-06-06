import Foundation

enum CodexAuthFileSwitcher {
    enum SwitchError: Error {
        case invalidJSON
    }

    private static let tokenKeys = ["access_token", "accessToken", "token"]
    private static let accountIDKeys = ["account_id", "accountId", "chatgpt_account_id", "chatgptAccountId"]
    private static let emailKeys = ["email", "user_email", "account_email", "emailAddress", "email_address"]
    private static let authModeKey = "auth_mode"
    private static let chatGPTAuthMode = "chatgpt"
    private static let tokenContainerKey = "tokens"
    private static let openAIAPIKey = "OPENAI_API_KEY"
    private static let codexAPIKey = "CODEX_API_KEY"
    private static let idTokenKey = "id_token"
    private static let lastRefreshKey = "last_refresh"

    static func rewriteAuthJSON(
        _ data: Data,
        accessToken: String,
        accountID: String,
        email: String?,
        idToken: String? = nil,
        lastRefresh: String? = nil
    ) throws -> Data {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            throw SwitchError.invalidJSON
        }

        var stats = RewriteStats()
        var rewritten = rewriteNode(
            jsonObject,
            accessToken: accessToken,
            accountID: accountID,
            email: email,
            stats: &stats
        )

        if var root = rewritten as? [String: Any] {
            normalizeRootAuthCache(
                &root,
                accessToken: accessToken,
                accountID: accountID,
                email: email,
                idToken: idToken,
                lastRefresh: lastRefresh,
                stats: stats
            )
            rewritten = root
        }

        return try JSONSerialization.data(withJSONObject: rewritten, options: [.prettyPrinted, .sortedKeys])
    }

    private struct RewriteStats {
        var replacedToken = false
        var replacedAccountID = false
        var replacedEmail = false
    }

    private static func rewriteNode(
        _ node: Any,
        accessToken: String,
        accountID: String,
        email: String?,
        stats: inout RewriteStats
    ) -> Any {
        if let dictionary = node as? [String: Any] {
            var output: [String: Any] = [:]
            for (key, value) in dictionary {
                if tokenKeys.contains(key) {
                    output[key] = accessToken
                    stats.replacedToken = true
                    continue
                }
                if accountIDKeys.contains(key) {
                    output[key] = accountID
                    stats.replacedAccountID = true
                    continue
                }
                if emailKeys.contains(key), let email, !email.isEmpty {
                    output[key] = email
                    stats.replacedEmail = true
                    continue
                }

                output[key] = rewriteNode(
                    value,
                    accessToken: accessToken,
                    accountID: accountID,
                    email: email,
                    stats: &stats
                )
            }
            return output
        }

        if let array = node as? [Any] {
            return array.map {
                rewriteNode(
                    $0,
                    accessToken: accessToken,
                    accountID: accountID,
                    email: email,
                    stats: &stats
                )
            }
        }

        return node
    }

    private static func normalizeRootAuthCache(
        _ root: inout [String: Any],
        accessToken: String,
        accountID: String,
        email: String?,
        idToken: String?,
        lastRefresh: String?,
        stats: RewriteStats
    ) {
        let usesModernAuthCache = root[authModeKey] != nil || root[tokenContainerKey] != nil

        guard usesModernAuthCache else {
            if !stats.replacedToken {
                root["access_token"] = accessToken
            }
            if !stats.replacedAccountID {
                root["account_id"] = accountID
            }
            if let email, !email.isEmpty, !stats.replacedEmail {
                root["email"] = email
            }
            return
        }

        root[authModeKey] = chatGPTAuthMode
        root[openAIAPIKey] = NSNull()
        root.removeValue(forKey: codexAPIKey)

        var tokens = root[tokenContainerKey] as? [String: Any] ?? [:]
        tokens["access_token"] = accessToken
        tokens["account_id"] = accountID
        if let idToken = nonEmptyString(idToken) {
            tokens[idTokenKey] = idToken
        }
        root[tokenContainerKey] = tokens
        if let lastRefresh = nonEmptyString(lastRefresh) {
            root[lastRefreshKey] = lastRefresh
        }

        for key in tokenKeys {
            root.removeValue(forKey: key)
        }
        for key in accountIDKeys {
            root.removeValue(forKey: key)
        }
        if let email, !email.isEmpty, !stats.replacedEmail {
            root["email"] = email
        }
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}
