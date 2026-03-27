import Foundation

struct PoolDashboardLocalAccountsCoordinator {
    struct BookmarkLoadResult {
        let didLoadAccounts: Bool
        let authorizedURL: URL?
    }

    func refreshLocalOAuthAccounts(
        state: inout AccountPoolState,
        viewModel: inout LocalOAuthImportViewModel,
        authFileAccessService: CodexAuthFileAccessService,
        currentAuthorizedAuthFileURL: URL?
    ) -> URL? {
        let bookmarkResult = loadLocalOAuthAccountsFromBookmark(
            state: &state,
            viewModel: &viewModel,
            authFileAccessService: authFileAccessService,
            currentAuthorizedAuthFileURL: currentAuthorizedAuthFileURL
        )
        if bookmarkResult.didLoadAccounts {
            return bookmarkResult.authorizedURL
        }

        let discovered = LocalCodexAccountDiscovery.discover()
        viewModel.applyAutomaticScanResult(discovered)
        normalizeStoredImportedAccountNames(state: &state, localAccounts: viewModel.accounts)
        return bookmarkResult.authorizedURL
    }

    func loadLocalOAuthAccounts(
        from url: URL,
        state: inout AccountPoolState,
        viewModel: inout LocalOAuthImportViewModel,
        authFileAccessService: CodexAuthFileAccessService
    ) {
        do {
            let accounts = try authFileAccessService.loadAccounts(from: url)
            viewModel.applyLoadedAccountsFromFile(accounts)
            normalizeStoredImportedAccountNames(state: &state, localAccounts: viewModel.accounts)
        } catch {
            viewModel.applyReadFailure(error)
        }
    }

    func saveAuthFileBookmark(
        for url: URL,
        viewModel: inout LocalOAuthImportViewModel,
        authFileAccessService: CodexAuthFileAccessService
    ) {
        do {
            try authFileAccessService.saveBookmark(for: url)
        } catch {
            viewModel.applyBookmarkSaveFailure(error)
        }
    }

    func loadLocalOAuthAccountsFromBookmark(
        state: inout AccountPoolState,
        viewModel: inout LocalOAuthImportViewModel,
        authFileAccessService: CodexAuthFileAccessService,
        currentAuthorizedAuthFileURL: URL?
    ) -> BookmarkLoadResult {
        guard authFileAccessService.hasSavedBookmark() else {
            return makeBookmarkFallbackResult(
                currentAuthorizedAuthFileURL: currentAuthorizedAuthFileURL
            )
        }

        do {
            let resolved = try authFileAccessService.loadAuthorizedURLFromBookmark()
            if resolved.wasStale {
                saveAuthFileBookmark(
                    for: resolved.url,
                    viewModel: &viewModel,
                    authFileAccessService: authFileAccessService
                )
            }
            loadLocalOAuthAccounts(
                from: resolved.url,
                state: &state,
                viewModel: &viewModel,
                authFileAccessService: authFileAccessService
            )
            return makeBookmarkSuccessResult(
                didLoadAccounts: !viewModel.accounts.isEmpty,
                authorizedURL: resolved.url
            )
        } catch {
            viewModel.applyBookmarkInvalid()
            return makeBookmarkFallbackResult(
                currentAuthorizedAuthFileURL: currentAuthorizedAuthFileURL
            )
        }
    }

    func hasSavedAuthFileBookmark(authFileAccessService: CodexAuthFileAccessService) -> Bool {
        authFileAccessService.hasSavedBookmark()
    }

    @MainActor
    func openAuthFilePanelAndLoad(
        state: inout AccountPoolState,
        viewModel: inout LocalOAuthImportViewModel,
        authFileAccessService: CodexAuthFileAccessService
    ) -> URL? {
        guard let url = CodexAuthFilePanelService().pickAuthFileURL() else {
#if !canImport(AppKit)
            viewModel.errorMessage = "目前平台不支援檔案面板"
#endif
            return nil
        }

        saveAuthFileBookmark(
            for: url,
            viewModel: &viewModel,
            authFileAccessService: authFileAccessService
        )
        loadLocalOAuthAccounts(
            from: url,
            state: &state,
            viewModel: &viewModel,
            authFileAccessService: authFileAccessService
        )
        return url
    }

    func normalizeStoredImportedAccountNames(
        state: inout AccountPoolState,
        localAccounts: [LocalCodexOAuthAccount]
    ) {
        for localAccount in localAccounts {
            guard let chatGPTAccountID = localAccount.chatGPTAccountID else { continue }
            guard let persisted = state.accounts.first(where: { $0.chatGPTAccountID == chatGPTAccountID }) else { continue }
            guard persisted.name == "Codex OAuth" else { continue }

            let improvedName = localAccount.email ?? localAccount.displayName
            guard !improvedName.isEmpty, improvedName != persisted.name else { continue }
            state.updateAccount(persisted.id, name: improvedName)
        }
    }

    private func makeBookmarkFallbackResult(
        currentAuthorizedAuthFileURL: URL?
    ) -> BookmarkLoadResult {
        BookmarkLoadResult(
            didLoadAccounts: false,
            authorizedURL: currentAuthorizedAuthFileURL
        )
    }

    private func makeBookmarkSuccessResult(
        didLoadAccounts: Bool,
        authorizedURL: URL
    ) -> BookmarkLoadResult {
        BookmarkLoadResult(
            didLoadAccounts: didLoadAccounts,
            authorizedURL: authorizedURL
        )
    }
}
