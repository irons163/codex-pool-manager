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
        tokenVault: AccountTokenVault = UserDefaultsAccountTokenVault()
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
        tokenVault.pruneTokens(keeping: Set(snapshot.accounts.map(\.id)))

        let redacted = snapshot.redactingAPITokens()

        guard let data = try? JSONEncoder().encode(redacted) else { return }
        defaults.set(data, forKey: key)
    }
}

struct DeveloperAwareAccountPoolStore: AccountPoolStoring {
    private let defaults: UserDefaults
    private let productionSnapshotKey: String
    private let productionTokenKey: String
    private let developerSnapshotKey: String
    private let developerTokenKey: String
    private let developerMockModeKey: String

    init(
        defaults: UserDefaults = .standard,
        productionSnapshotKey: String = "account_pool_snapshot",
        productionTokenKey: String = "account_pool_tokens",
        developerSnapshotKey: String = "account_pool_snapshot_developer",
        developerTokenKey: String = "account_pool_tokens_developer",
        developerMockModeKey: String = "pool_dashboard.developer.mock_mode"
    ) {
        self.defaults = defaults
        self.productionSnapshotKey = productionSnapshotKey
        self.productionTokenKey = productionTokenKey
        self.developerSnapshotKey = developerSnapshotKey
        self.developerTokenKey = developerTokenKey
        self.developerMockModeKey = developerMockModeKey
    }

    func load() -> AccountPoolSnapshot? {
        resolvedStore.load()
    }

    func save(_ snapshot: AccountPoolSnapshot) {
        resolvedStore.save(snapshot)
    }

    private var resolvedStore: UserDefaultsAccountPoolStore {
        #if DEBUG
        if defaults.bool(forKey: developerMockModeKey) {
            return UserDefaultsAccountPoolStore(
                defaults: defaults,
                key: developerSnapshotKey,
                tokenVault: UserDefaultsAccountTokenVault(defaults: defaults, key: developerTokenKey)
            )
        }
        #endif

        return UserDefaultsAccountPoolStore(
            defaults: defaults,
            key: productionSnapshotKey,
            tokenVault: UserDefaultsAccountTokenVault(defaults: defaults, key: productionTokenKey)
        )
    }
}
