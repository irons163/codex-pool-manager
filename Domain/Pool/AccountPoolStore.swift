import Foundation

protocol AccountPoolStoring {
    func load() -> AccountPoolSnapshot?
    func save(_ snapshot: AccountPoolSnapshot)
    func apiToken(for accountID: UUID) -> String?
    func removeToken(for accountID: UUID)
}

extension AccountPoolStoring {
    func apiToken(for accountID: UUID) -> String? {
        load()?
            .accounts
            .first(where: { $0.id == accountID })?
            .apiToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func removeToken(for accountID: UUID) {}
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
            let snapshotToken = snapshot.accounts[index].apiToken
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let vaultToken = tokenVault.token(for: accountID)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !vaultToken.isEmpty {
                snapshot.accounts[index].apiToken = vaultToken
            } else if !snapshotToken.isEmpty {
                snapshot.accounts[index].apiToken = snapshotToken
                tokenVault.setToken(snapshotToken, for: accountID)
            } else {
                snapshot.accounts[index].apiToken = ""
            }
        }
        return snapshot
    }

    func save(_ snapshot: AccountPoolSnapshot) {
        for account in snapshot.accounts {
            let normalizedToken = account.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedToken.isEmpty {
                tokenVault.setToken(normalizedToken, for: account.id)
            }
        }
        // Intentionally NOT pruning the vault here. `save` runs on every snapshot
        // change, sometimes with a stale or empty in-memory snapshot (e.g. a
        // startup save before state has loaded, or a test host booting on real
        // prefs). Pruning to the saved snapshot's account set would then delete
        // still-valid tokens permanently, since the persisted snapshot is redacted
        // and there is no other copy. Tokens for genuinely deleted accounts are
        // removed explicitly via `removeToken(for:)` from the delete flow.

        let redacted = snapshot.redactingAPITokens()

        guard let data = try? JSONEncoder().encode(redacted) else { return }
        defaults.set(data, forKey: key)
    }

    func apiToken(for accountID: UUID) -> String? {
        if let vaultToken = tokenVault.token(for: accountID)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !vaultToken.isEmpty {
            return vaultToken
        }

        return load()?
            .accounts
            .first(where: { $0.id == accountID })?
            .apiToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func removeToken(for accountID: UUID) {
        tokenVault.removeToken(for: accountID)
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

    func apiToken(for accountID: UUID) -> String? {
        resolvedStore.apiToken(for: accountID)
    }

    func removeToken(for accountID: UUID) {
        resolvedStore.removeToken(for: accountID)
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
