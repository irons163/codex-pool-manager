import Foundation

struct PoolDashboardSwitchLaunchFlowCoordinator {
    struct Output {
        let viewModel: LocalOAuthImportViewModel
        let viewState: PoolDashboardViewState
        let sessionAuthorizedAuthFileURL: URL?
    }

    private let switchLaunchCoordinator = PoolDashboardSwitchLaunchCoordinator()
    private let mutationCoordinator = PoolDashboardMutationCoordinator()

    @MainActor
    func switchAndLaunch(
        using account: AgentAccount,
        currentAuthorizedAuthFileURL: URL?,
        authFileAccessService: CodexAuthFileAccessService,
        viewModel: LocalOAuthImportViewModel,
        viewState: PoolDashboardViewState,
        authorizeAuthFile: @escaping @MainActor () -> URL?
    ) async -> Output {
        var nextViewModel = viewModel
        var nextViewState = viewState
        var nextSessionAuthorizedAuthFileURL = currentAuthorizedAuthFileURL

        let switchOutput = await switchLaunchCoordinator.switchAndLaunch(
            account: account,
            currentAuthorizedAuthFileURL: currentAuthorizedAuthFileURL,
            authFileAccessService: authFileAccessService,
            authorizeAuthFile: authorizeAuthFile
        )
        mutationCoordinator.applySwitchOutput(
            switchOutput,
            viewModel: &nextViewModel,
            viewState: &nextViewState,
            sessionAuthorizedAuthFileURL: &nextSessionAuthorizedAuthFileURL
        )

        return makeOutput(
            viewModel: nextViewModel,
            viewState: nextViewState,
            sessionAuthorizedAuthFileURL: nextSessionAuthorizedAuthFileURL
        )
    }

    private func makeOutput(
        viewModel: LocalOAuthImportViewModel,
        viewState: PoolDashboardViewState,
        sessionAuthorizedAuthFileURL: URL?
    ) -> Output {
        Output(
            viewModel: viewModel,
            viewState: viewState,
            sessionAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL
        )
    }
}
