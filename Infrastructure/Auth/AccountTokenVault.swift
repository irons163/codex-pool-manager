import Foundation

struct OAuthCredential: Equatable, Codable {
    var accessToken: String
    var refreshToken: String?
    var idToken: String?
    var lastRefreshAt: Date?

    init(
        accessToken: String,
        refreshToken: String? = nil,
        idToken: String? = nil,
        lastRefreshAt: Date? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.lastRefreshAt = lastRefreshAt
    }
}

protocol AccountTokenVault {
    func token(for accountID: UUID) -> String?
    func setToken(_ token: String, for accountID: UUID)
    func oauthCredential(for accountID: UUID) -> OAuthCredential?
    func setOAuthCredential(_ credential: OAuthCredential, for accountID: UUID)
    func removeToken(for accountID: UUID)
    var tokenCount: Int { get }
    @discardableResult
    func pruneTokens(keeping accountIDs: Set<UUID>) -> Int
}

final class InMemoryAccountTokenVault: AccountTokenVault {
    private var storage: [UUID: OAuthCredential] = [:]

    func token(for accountID: UUID) -> String? {
        storage[accountID]?.accessToken
    }

    func setToken(_ token: String, for accountID: UUID) {
        storage[accountID] = OAuthCredential(accessToken: token)
    }

    func oauthCredential(for accountID: UUID) -> OAuthCredential? {
        storage[accountID]
    }

    func setOAuthCredential(_ credential: OAuthCredential, for accountID: UUID) {
        storage[accountID] = credential
    }

    func removeToken(for accountID: UUID) {
        storage.removeValue(forKey: accountID)
    }

    var tokenCount: Int {
        storage.count
    }

    @discardableResult
    func pruneTokens(keeping accountIDs: Set<UUID>) -> Int {
        let before = storage.count
        storage = storage.filter { accountIDs.contains($0.key) }
        return before - storage.count
    }
}

final class UserDefaultsAccountTokenVault: AccountTokenVault {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "account_pool_tokens") {
        self.defaults = defaults
        self.key = key
    }

    func token(for accountID: UUID) -> String? {
        oauthCredential(for: accountID)?.accessToken
    }

    func setToken(_ token: String, for accountID: UUID) {
        setOAuthCredential(OAuthCredential(accessToken: token), for: accountID)
    }

    func oauthCredential(for accountID: UUID) -> OAuthCredential? {
        guard let raw = storage[accountID.uuidString] else { return nil }
        return Self.decodeCredential(from: raw)
    }

    func setOAuthCredential(_ credential: OAuthCredential, for accountID: UUID) {
        var next = storage
        next[accountID.uuidString] = Self.encodeCredential(credential)
        defaults.set(next, forKey: key)
    }

    func removeToken(for accountID: UUID) {
        var next = storage
        next.removeValue(forKey: accountID.uuidString)
        defaults.set(next, forKey: key)
    }

    var tokenCount: Int {
        storage.count
    }

    @discardableResult
    func pruneTokens(keeping accountIDs: Set<UUID>) -> Int {
        let allowedKeys = Set(accountIDs.map(\.uuidString))
        let before = storage
        let next = before.filter { allowedKeys.contains($0.key) }
        guard next.count != before.count else { return 0 }
        defaults.set(next, forKey: key)
        return before.count - next.count
    }

    private var storage: [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private static func decodeCredential(from raw: String) -> OAuthCredential? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let data = trimmed.data(using: .utf8),
           let credential = try? JSONDecoder().decode(OAuthCredential.self, from: data) {
            return credential
        }
        return OAuthCredential(accessToken: trimmed)
    }

    private static func encodeCredential(_ credential: OAuthCredential) -> String {
        if let data = try? JSONEncoder().encode(credential),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        return credential.accessToken
    }
}
