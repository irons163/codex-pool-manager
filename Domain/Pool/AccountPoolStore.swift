import Foundation

protocol AccountPoolStoring {
    func load() -> AccountPoolSnapshot?
    func save(_ snapshot: AccountPoolSnapshot)
}

struct UserDefaultsAccountPoolStore: AccountPoolStoring {
    private let defaults: UserDefaults
    private let key: String
    private let tokenVault: AccountTokenVault

    init(
        defaults: UserDefaults = .standard,
        key: String = "account_pool_snapshot",
        tokenVault: AccountTokenVault = KeychainAccountTokenVault()
    ) {
        self.defaults = defaults
        self.key = key
        self.tokenVault = tokenVault
    }

    func load() -> AccountPoolSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard var snapshot = try? JSONDecoder().decode(AccountPoolSnapshot.self, from: data) else {
            return nil
        }
        for index in snapshot.accounts.indices {
            let accountID = snapshot.accounts[index].id
            snapshot.accounts[index].apiToken = tokenVault.token(for: accountID) ?? ""
        }
        return snapshot
    }

    func save(_ snapshot: AccountPoolSnapshot) {
        for account in snapshot.accounts {
            if account.apiToken.isEmpty {
                tokenVault.removeToken(for: account.id)
            } else {
                tokenVault.setToken(account.apiToken, for: account.id)
            }
        }

        let redacted = snapshot.redactingAPITokens()

        guard let data = try? JSONEncoder().encode(redacted) else { return }
        defaults.set(data, forKey: key)
    }
}
