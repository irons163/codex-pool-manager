import Foundation

struct PoolDashboardBackupFlowCoordinator {
    private let backupCoordinator = PoolDashboardBackupCoordinator()
    private let mutationCoordinator = PoolDashboardMutationCoordinator()

    func exportSnapshot(
        from state: AccountPoolState,
        viewState: inout PoolDashboardViewState
    ) {
        applyExportResult(
            from: state,
            viewState: &viewState,
            exporter: backupCoordinator.exportSnapshot
        )
    }

    func exportRefetchableSnapshot(
        from state: AccountPoolState,
        viewState: inout PoolDashboardViewState
    ) {
        applyExportResult(
            from: state,
            viewState: &viewState,
            exporter: backupCoordinator.exportRefetchableSnapshot
        )
    }

    func importSnapshot(
        state: inout AccountPoolState,
        viewState: inout PoolDashboardViewState
    ) -> Bool {
        let result = backupCoordinator.importSnapshotState(from: viewState.backupJSON)
        return mutationCoordinator.applyBackupImportResult(
            result,
            state: &state,
            viewState: &viewState
        )
    }

    private func applyExportResult(
        from state: AccountPoolState,
        viewState: inout PoolDashboardViewState,
        exporter: (AccountPoolSnapshot) -> (json: String?, errorMessage: String?)
    ) {
        let result = exporter(state.snapshot)
        mutationCoordinator.applyBackupExportResult(result, viewState: &viewState)
    }
}
