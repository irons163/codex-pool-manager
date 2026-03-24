import Foundation

protocol AuthFileAccessing {
    func hasSavedBookmark() -> Bool
    func resolveBookmarkedAuthURL() throws -> URL?
    func saveBookmark(for url: URL) throws
    func loadAccounts(from url: URL) throws -> [LocalCodexOAuthAccount]
    func autoDiscoverAccounts() -> [LocalCodexOAuthAccount]
}

struct DefaultAuthFileAccess: AuthFileAccessing {
    private let bookmarkKey = "codex_auth_json_bookmark"

    func hasSavedBookmark() -> Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    func resolveBookmarkedAuthURL() throws -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return nil
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            try saveBookmark(for: url)
        }
        return url
    }

    func saveBookmark(for url: URL) throws {
        let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    }

    func loadAccounts(from url: URL) throws -> [LocalCodexOAuthAccount] {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        return LocalCodexAccountDiscovery.parseAccounts(from: data, source: url.path)
    }

    func autoDiscoverAccounts() -> [LocalCodexOAuthAccount] {
        LocalCodexAccountDiscovery.discover()
    }
}

struct LocalOAuthImportViewModel {
    private let authAccess: any AuthFileAccessing

    private(set) var localOAuthAccounts: [LocalCodexOAuthAccount]
    private(set) var localOAuthError: String?

    init(
        authAccess: any AuthFileAccessing = DefaultAuthFileAccess(),
        localOAuthAccounts: [LocalCodexOAuthAccount] = [],
        localOAuthError: String? = nil
    ) {
        self.authAccess = authAccess
        self.localOAuthAccounts = localOAuthAccounts
        self.localOAuthError = localOAuthError
    }

    mutating func refresh() {
        if loadFromBookmarkIfPossible() {
            return
        }

        let discovered = authAccess.autoDiscoverAccounts()
        localOAuthAccounts = discovered

        if discovered.isEmpty {
            localOAuthError = "自動掃描沒有讀到帳號，可能是 macOS Sandbox 限制。請按「選擇 auth.json」授權。"
        } else {
            localOAuthError = nil
        }
    }

    mutating func handleSelectedAuthFile(_ url: URL) {
        do {
            try authAccess.saveBookmark(for: url)
            let accounts = try authAccess.loadAccounts(from: url)
            localOAuthAccounts = accounts
            localOAuthError = accounts.isEmpty ? "檔案格式可讀，但未找到 access token" : nil
        } catch {
            localOAuthError = "讀取失敗：\(error.localizedDescription)"
        }
    }

    mutating func importAccount(_ localAccount: LocalCodexOAuthAccount, into state: inout AccountPoolState) {
        if state.accounts.contains(where: { $0.apiToken == localAccount.accessToken }) {
            localOAuthError = "此帳號已在帳號池"
            return
        }

        let name = localAccount.email ?? localAccount.displayName
        let newAccountID = state.addAccount(name: name, quota: 1000)
        state.updateAccount(newAccountID, apiToken: localAccount.accessToken)
        localOAuthError = nil
    }

    private mutating func loadFromBookmarkIfPossible() -> Bool {
        do {
            guard let url = try authAccess.resolveBookmarkedAuthURL() else {
                return false
            }
            let accounts = try authAccess.loadAccounts(from: url)
            localOAuthAccounts = accounts
            localOAuthError = accounts.isEmpty ? "檔案格式可讀，但未找到 access token" : nil
            return !accounts.isEmpty
        } catch {
            localOAuthError = "授權已失效，請重新選擇 auth.json"
            return false
        }
    }
}
