import Foundation

protocol AccountPoolStoring {
    func load() -> AccountPoolSnapshot?
    func save(_ snapshot: AccountPoolSnapshot)
}

struct UserDefaultsAccountPoolStore: AccountPoolStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "account_pool_snapshot") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> AccountPoolSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AccountPoolSnapshot.self, from: data)
    }

    func save(_ snapshot: AccountPoolSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
