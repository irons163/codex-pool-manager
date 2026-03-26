import Foundation

struct PoolDashboardLocalImportFlowCoordinator {
    struct Output {
        let state: AccountPoolState
        let viewModel: LocalOAuthImportViewModel
        let viewState: PoolDashboardViewState
    }

    private let localImportCoordinator = PoolDashboardLocalImportCoordinator()
    private let mutationCoordinator = PoolDashboardMutationCoordinator()

    @MainActor
    func importLocalOAuthAccount(
        _ localAccount: LocalCodexOAuthAccount,
        from state: AccountPoolState,
        viewModel: LocalOAuthImportViewModel,
        viewState: PoolDashboardViewState,
        onRawResponse: @escaping @MainActor (String) -> Void
    ) async -> Output {
        var nextState = state
        var nextViewModel = viewModel
        var nextViewState = viewState

        let localImportOutput = await localImportCoordinator.importLocalOAuthAccount(
            localAccount,
            state: state,
            viewModel: viewModel,
            onRawResponse: onRawResponse
        )
        mutationCoordinator.applyLocalImportOutput(
            localImportOutput,
            state: &nextState,
            viewModel: &nextViewModel,
            viewState: &nextViewState
        )

        return makeOutput(
            state: nextState,
            viewModel: nextViewModel,
            viewState: nextViewState
        )
    }

    private func makeOutput(
        state: AccountPoolState,
        viewModel: LocalOAuthImportViewModel,
        viewState: PoolDashboardViewState
    ) -> Output {
        Output(
            state: state,
            viewModel: viewModel,
            viewState: viewState
        )
    }
}
