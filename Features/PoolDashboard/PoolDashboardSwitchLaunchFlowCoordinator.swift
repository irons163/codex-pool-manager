import Foundation

struct PoolDashboardSwitchLaunchFlowCoordinator {
    struct Output {
        let viewModel: LocalOAuthImportViewModel
        let viewState: PoolDashboardViewState
        let sessionAuthorizedAuthFileURL: URL?
        let didSwitchAuth: Bool
    }

    private let switchLaunchCoordinator = PoolDashboardSwitchLaunchCoordinator()
    private let mutationCoordinator = PoolDashboardMutationCoordinator()

    @MainActor
    func switchAndLaunch(
        using account: AgentAccount,
        switchWithoutLaunching: Bool = false,
        launchTarget: CodexLaunchTarget = .auto,
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
            switchWithoutLaunching: switchWithoutLaunching,
            launchTarget: launchTarget,
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
            sessionAuthorizedAuthFileURL: nextSessionAuthorizedAuthFileURL,
            didSwitchAuth: switchOutput.didSwitchAuth
        )
    }

    private func makeOutput(
        viewModel: LocalOAuthImportViewModel,
        viewState: PoolDashboardViewState,
        sessionAuthorizedAuthFileURL: URL?,
        didSwitchAuth: Bool
    ) -> Output {
        Output(
            viewModel: viewModel,
            viewState: viewState,
            sessionAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL,
            didSwitchAuth: didSwitchAuth
        )
    }
}
