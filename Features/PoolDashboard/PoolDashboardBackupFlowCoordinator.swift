import Foundation

struct PoolDashboardBackupFlowCoordinator {
    private let backupCoordinator = PoolDashboardBackupCoordinator()
    private let mutationCoordinator = PoolDashboardMutationCoordinator()

    func exportSnapshot(
        from state: AccountPoolState,
        viewState: inout PoolDashboardViewState
    ) {
        let result = backupCoordinator.exportSnapshot(from: state.snapshot)
        mutationCoordinator.applyBackupExportResult(result, viewState: &viewState)
    }

    func exportRefetchableSnapshot(
        from state: AccountPoolState,
        viewState: inout PoolDashboardViewState
    ) {
        let result = backupCoordinator.exportRefetchableSnapshot(from: state.snapshot)
        mutationCoordinator.applyBackupExportResult(result, viewState: &viewState)
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
}
