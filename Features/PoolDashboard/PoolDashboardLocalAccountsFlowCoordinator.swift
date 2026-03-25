import Foundation

struct PoolDashboardLocalAccountsFlowCoordinator {
    struct Output {
        let state: AccountPoolState
        let viewModel: LocalOAuthImportViewModel
        let sessionAuthorizedAuthFileURL: URL?
        let pickedAuthFileURL: URL?
    }

    private let localAccountsCoordinator = PoolDashboardLocalAccountsCoordinator()

    func refreshLocalOAuthAccounts(
        from state: AccountPoolState,
        viewModel: LocalOAuthImportViewModel,
        authFileAccessService: CodexAuthFileAccessService,
        currentAuthorizedAuthFileURL: URL?
    ) -> Output {
        var nextState = state
        var nextViewModel = viewModel
        let nextSessionAuthorizedAuthFileURL = localAccountsCoordinator.refreshLocalOAuthAccounts(
            state: &nextState,
            viewModel: &nextViewModel,
            authFileAccessService: authFileAccessService,
            currentAuthorizedAuthFileURL: currentAuthorizedAuthFileURL
        )
        return Output(
            state: nextState,
            viewModel: nextViewModel,
            sessionAuthorizedAuthFileURL: nextSessionAuthorizedAuthFileURL,
            pickedAuthFileURL: nil
        )
    }

    @MainActor
    func openAuthFilePanel(
        from state: AccountPoolState,
        viewModel: LocalOAuthImportViewModel,
        currentAuthorizedAuthFileURL: URL?,
        authFileAccessService: CodexAuthFileAccessService
    ) -> Output {
        var nextState = state
        var nextViewModel = viewModel
        let pickedURL = localAccountsCoordinator.openAuthFilePanelAndLoad(
            state: &nextState,
            viewModel: &nextViewModel,
            authFileAccessService: authFileAccessService
        )
        let nextSessionAuthorizedAuthFileURL = pickedURL ?? currentAuthorizedAuthFileURL
        return Output(
            state: nextState,
            viewModel: nextViewModel,
            sessionAuthorizedAuthFileURL: nextSessionAuthorizedAuthFileURL,
            pickedAuthFileURL: pickedURL
        )
    }
}
