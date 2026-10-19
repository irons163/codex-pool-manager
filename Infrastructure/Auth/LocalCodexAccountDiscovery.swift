import Foundation

struct LocalCodexOAuthAccount: Identifiable, Equatable {
    let id: String
    let displayName: String
    let email: String?
    let source: String
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let chatGPTAccountID: String?

    init(
        id: String,
        displayName: String,
        email: String?,
        source: String,
        accessToken: String,
        refreshToken: String? = nil,
        idToken: String? = nil,
        chatGPTAccountID: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.source = source
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.chatGPTAccountID = chatGPTAccountID
    }

    var maskedToken: String {
        guard accessToken.count > 10 else { return "********" }
        let prefix = accessToken.prefix(6)
        let suffix = accessToken.suffix(4)
        return "\(prefix)...\(suffix)"
    }
}

enum LocalCodexAccountDiscovery {
    private static let emailKeys = [
        "email",
        "user_email",
        "account_email",
        "primary_email",
        "email_address",
        "emailAddress",
        "username",
        "login"
    ]
    private static let displayNameKeys = ["name", "display_name", "user_name", "account_name"]
    private static let accountIDKeys = ["account_id", "accountId", "chatgpt_account_id", "chatgptAccountId"]
    private static let accessTokenKeys = ["access_token", "accessToken"]
    private static let refreshTokenKeys = ["refresh_token", "refreshToken"]
    private static let idTokenKeys = ["id_token", "idToken"]

    static func discover(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [LocalCodexOAuthAccount] {
        var discovered: [LocalCodexOAuthAccount] = []
        for path in candidateAuthFiles(homeDirectory: homeDirectory) {
            guard fileManager.fileExists(atPath: path.path) else { continue }
            guard let data = try? Data(contentsOf: path) else { continue }
            discovered.append(contentsOf: parseAccounts(from: data, source: path.path))
        }
        return deduplicated(discovered)
    }

    static func parseAccounts(from data: Data, source: String) -> [LocalCodexOAuthAccount] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return deduplicated(extractAccounts(from: root, source: source))
    }

    /// Codex can rotate credentials while the pool still holds an older copy.
    /// Match both the workspace and its user; workspace membership alone is not identity.
    static func newerTokens(
        for account: AgentAccount,
        in localAccounts: [LocalCodexOAuthAccount]
    ) -> OAuthTokens? {
        guard account.supportsCodexUsageSync,
              let accountID = OAuthIDTokenClaims.nonEmpty(account.chatGPTAccountID)?.lowercased()
        else { return nil }

        let currentIdentityIsValid = !OAuthIDTokenClaimsParser.hasConflictingAccountID(
            accountID, accessToken: account.apiToken, idToken: account.oauthIDToken
        ) && OAuthIDTokenClaimsParser.matchesUser(of: account, accessToken: account.apiToken, idToken: account.oauthIDToken)
        let currentIssuedAt = currentIdentityIsValid ? OAuthIDTokenClaimsParser.issuedAt(account.apiToken) : nil
        let candidates = localAccounts.compactMap { local -> (OAuthTokens, Date)? in
            let tokens = OAuthTokens(
                accessToken: local.accessToken,
                refreshToken: OAuthIDTokenClaims.nonEmpty(local.refreshToken),
                idToken: OAuthIDTokenClaims.nonEmpty(local.idToken)
            )
            let claims = OAuthIDTokenClaimsParser.parse(tokens: tokens)
            let tokenAccountID = OAuthIDTokenClaimsParser.parse(local.accessToken)?.accountID
                ?? claims?.accountID
            guard OAuthIDTokenClaims.nonEmpty(tokenAccountID)?.lowercased() == accountID,
                  local.chatGPTAccountID.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == accountID }) ?? true,
                  !OAuthIDTokenClaimsParser.hasConflictingAccountID(
                    accountID, accessToken: tokens.accessToken, idToken: tokens.idToken ?? account.oauthIDToken
                  ),
                  OAuthIDTokenClaimsParser.matchesUser(
                    of: account, accessToken: tokens.accessToken, idToken: tokens.idToken,
                    requireProof: true
                  ),
                  tokens.refreshToken != nil,
                  let issuedAt = OAuthIDTokenClaimsParser.issuedAt(local.accessToken)
            else { return nil }

            if local.accessToken == account.apiToken {
                // Fill missing metadata only; an old cache must not replace a
                // refresh token that the pool has already rotated.
                guard OAuthIDTokenClaims.nonEmpty(account.oauthRefreshToken) == nil else { return nil }
            } else {
                guard issuedAt > (currentIssuedAt ?? .distantPast) else { return nil }
            }
            return (tokens, issuedAt)
        }
        return candidates.max(by: { $0.1 < $1.1 })?.0
    }

    private static func extractAccounts(from node: Any, source: String) -> [LocalCodexOAuthAccount] {
        var accounts: [LocalCodexOAuthAccount] = []

        if let dictionary = node as? [String: Any] {
            if let accessToken = findAccessToken(in: dictionary) {
                let email = findStringDeep(in: dictionary, keys: emailKeys)
                let name = findStringDeep(in: dictionary, keys: displayNameKeys) ?? email ?? L10n.text("account.default_oauth_name")
                let chatGPTAccountID = findStringDeep(in: dictionary, keys: accountIDKeys)
                let refreshToken = findStringDeep(in: dictionary, keys: refreshTokenKeys)
                let idToken = findStringDeep(in: dictionary, keys: idTokenKeys)
                let id = "\(source)|\(chatGPTAccountID ?? (email ?? name))|\(accessToken.prefix(16))"
                accounts.append(
                    LocalCodexOAuthAccount(
                        id: id,
                        displayName: name,
                        email: email,
                        source: source,
                        accessToken: accessToken,
                        refreshToken: refreshToken,
                        idToken: idToken,
                        chatGPTAccountID: chatGPTAccountID
                    )
                )
            }

            for value in dictionary.values {
                accounts.append(contentsOf: extractAccounts(from: value, source: source))
            }
        } else if let array = node as? [Any] {
            for value in array {
                accounts.append(contentsOf: extractAccounts(from: value, source: source))
            }
        }

        return accounts
    }

    private static func findAccessToken(in dictionary: [String: Any]) -> String? {
        let token = findString(in: dictionary, keys: ["token"])
        let candidates = [
            findString(in: dictionary, keys: accessTokenKeys),
            token?.hasPrefix("sk-") == true ? token : nil
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private static func candidateAuthFiles(homeDirectory: URL) -> [URL] {
        let primaryFiles = [
            homeDirectory.appending(path: ".codex/auth.json"),
            homeDirectory.appending(path: ".config/codex/auth.json"),
            homeDirectory.appending(path: ".openai/auth.json")
        ]
        return primaryFiles.flatMap { primary in
            let directory = primary.deletingLastPathComponent().appending(path: "auth_accounts")
            let cachedAccounts = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            return [primary] + cachedAccounts
                .filter { $0.pathExtension.lowercased() == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
    }

    private static func findString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                return value
            }
        }
        return nil
    }

    private static func findStringDeep(in node: Any, keys: [String]) -> String? {
        if let dictionary = node as? [String: Any] {
            if let value = findString(in: dictionary, keys: keys) {
                return value
            }
            for value in dictionary.values {
                if let nested = findStringDeep(in: value, keys: keys) {
                    return nested
                }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let nested = findStringDeep(in: value, keys: keys) {
                    return nested
                }
            }
        }
        return nil
    }

    private static func deduplicated(_ accounts: [LocalCodexOAuthAccount]) -> [LocalCodexOAuthAccount] {
        var seen = Set<String>()
        var output: [LocalCodexOAuthAccount] = []

        for account in accounts {
            let key = "\(account.chatGPTAccountID ?? "")|\(account.email ?? account.displayName)|\(account.accessToken)"
            if seen.insert(key).inserted {
                output.append(account)
            }
        }

        return output
    }
}
