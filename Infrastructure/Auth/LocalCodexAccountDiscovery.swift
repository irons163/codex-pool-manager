import Foundation

struct LocalCodexOAuthAccount: Identifiable, Equatable {
    let id: String
    let displayName: String
    let email: String?
    let source: String
    let accessToken: String
    let chatGPTAccountID: String?

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

    private static func extractAccounts(from node: Any, source: String) -> [LocalCodexOAuthAccount] {
        var accounts: [LocalCodexOAuthAccount] = []

        if let dictionary = node as? [String: Any] {
            if let accessToken = findAccessToken(in: dictionary) {
                let email = findStringDeep(in: dictionary, keys: emailKeys)
                let name = findStringDeep(in: dictionary, keys: displayNameKeys) ?? email ?? "Codex OAuth"
                let chatGPTAccountID = findStringDeep(in: dictionary, keys: accountIDKeys)
                let id = "\(source)|\(chatGPTAccountID ?? (email ?? name))|\(accessToken.prefix(16))"
                accounts.append(
                    LocalCodexOAuthAccount(
                        id: id,
                        displayName: name,
                        email: email,
                        source: source,
                        accessToken: accessToken,
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
        [
            homeDirectory.appending(path: ".codex/auth.json"),
            homeDirectory.appending(path: ".config/codex/auth.json"),
            homeDirectory.appending(path: ".openai/auth.json")
        ]
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
            let key = "\(account.email ?? account.displayName)|\(account.accessToken)"
            if seen.insert(key).inserted {
                output.append(account)
            }
        }

        return output
    }
}
