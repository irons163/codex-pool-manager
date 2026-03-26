import Foundation

struct PoolDashboardUsageSyncFlowCoordinator {
    struct Output {
        let state: AccountPoolState
        let viewState: PoolDashboardViewState
    }

    private let runtimeCoordinator = PoolDashboardRuntimeCoordinator()
    private let mutationCoordinator = PoolDashboardMutationCoordinator()

    func syncCodexUsage(
        from state: AccountPoolState,
        viewState: PoolDashboardViewState
    ) async -> Output {
        var nextState = state
        var nextViewState = viewState
        let runtimeOutput = await runtimeCoordinator.syncCodexUsage(from: state)
        mutationCoordinator.applySyncOutput(
            runtimeOutput,
            state: &nextState,
            viewState: &nextViewState
        )
        return Output(state: nextState, viewState: nextViewState)
    }
}
