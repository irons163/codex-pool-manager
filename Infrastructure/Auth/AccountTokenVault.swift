import Foundation

protocol AccountTokenVault {
    func token(for accountID: UUID) -> String?
    func setToken(_ token: String, for accountID: UUID)
    func removeToken(for accountID: UUID)
}

final class InMemoryAccountTokenVault: AccountTokenVault {
    private var storage: [UUID: String] = [:]

    func token(for accountID: UUID) -> String? {
        storage[accountID]
    }

    func setToken(_ token: String, for accountID: UUID) {
        storage[accountID] = token
    }

    func removeToken(for accountID: UUID) {
        storage.removeValue(forKey: accountID)
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
        storage[accountID.uuidString]
    }

    func setToken(_ token: String, for accountID: UUID) {
        var next = storage
        next[accountID.uuidString] = token
        defaults.set(next, forKey: key)
    }

    func removeToken(for accountID: UUID) {
        var next = storage
        next.removeValue(forKey: accountID.uuidString)
        defaults.set(next, forKey: key)
    }

    private var storage: [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}
