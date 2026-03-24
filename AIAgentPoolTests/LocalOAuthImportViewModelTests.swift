import Foundation
import Testing
@testable import AIAgentPool

struct LocalOAuthImportViewModelTests {

    @Test
    func refreshUsesBookmarkDataWhenAvailable() {
        let token = "token-bookmark-123"
        let account = LocalCodexOAuthAccount(
            id: "1",
            displayName: "Bookmarked",
            email: "bookmarked@example.com",
            source: "/tmp/auth.json",
            accessToken: token
        )
        let access = MockAuthFileAccess(
            bookmarkURL: URL(fileURLWithPath: "/tmp/auth.json"),
            bookmarkAccounts: [account],
            autoDiscoveredAccounts: []
        )
        var viewModel = LocalOAuthImportViewModel(authAccess: access)

        viewModel.refresh()

        #expect(viewModel.localOAuthAccounts.count == 1)
        #expect(viewModel.localOAuthAccounts.first?.accessToken == token)
        #expect(viewModel.localOAuthError == nil)
    }

    @Test
    func refreshFallsBackToAutoScanAndShowsHintWhenEmpty() {
        let access = MockAuthFileAccess(
            bookmarkURL: nil,
            bookmarkAccounts: [],
            autoDiscoveredAccounts: []
        )
        var viewModel = LocalOAuthImportViewModel(authAccess: access)

        viewModel.refresh()

        #expect(viewModel.localOAuthAccounts.isEmpty)
        #expect(viewModel.localOAuthError?.contains("選擇 auth.json") == true)
    }

    @Test
    func importRejectsDuplicatedToken() {
        let token = "token-dup-123"
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: UUID(), name: "A", usedUnits: 0, quota: 1000, apiToken: token)
            ],
            mode: .manual
        )
        let access = MockAuthFileAccess(bookmarkURL: nil, bookmarkAccounts: [], autoDiscoveredAccounts: [])
        var viewModel = LocalOAuthImportViewModel(authAccess: access)
        let account = LocalCodexOAuthAccount(
            id: "1",
            displayName: "Duplicated",
            email: nil,
            source: "source",
            accessToken: token
        )

        viewModel.importAccount(account, into: &state)

        #expect(state.accounts.count == 1)
        #expect(viewModel.localOAuthError == "此帳號已在帳號池")
    }

    @Test
    func importAddsNewAccount() {
        var state = AccountPoolState(accounts: [], mode: .manual)
        let access = MockAuthFileAccess(bookmarkURL: nil, bookmarkAccounts: [], autoDiscoveredAccounts: [])
        var viewModel = LocalOAuthImportViewModel(authAccess: access)
        let account = LocalCodexOAuthAccount(
            id: "1",
            displayName: "New",
            email: "new@example.com",
            source: "source",
            accessToken: "token-new-123"
        )

        viewModel.importAccount(account, into: &state)

        #expect(state.accounts.count == 1)
        #expect(state.accounts[0].apiToken == "token-new-123")
        #expect(viewModel.localOAuthError == nil)
    }
}

private struct MockAuthFileAccess: AuthFileAccessing {
    let bookmarkURL: URL?
    let bookmarkAccounts: [LocalCodexOAuthAccount]
    let autoDiscoveredAccounts: [LocalCodexOAuthAccount]

    func hasSavedBookmark() -> Bool {
        bookmarkURL != nil
    }

    func resolveBookmarkedAuthURL() throws -> URL? {
        bookmarkURL
    }

    func saveBookmark(for url: URL) throws {
        _ = url
    }

    func loadAccounts(from url: URL) throws -> [LocalCodexOAuthAccount] {
        _ = url
        return bookmarkAccounts
    }

    func autoDiscoverAccounts() -> [LocalCodexOAuthAccount] {
        autoDiscoveredAccounts
    }
}
