import Foundation

struct PoolDashboardBackupFlowCoordinator {
    private let backupCoordinator = PoolDashboardBackupCoordinator()
    private let mutationCoordinator = PoolDashboardMutationCoordinator()

    func exportSnapshot(
        from state: AccountPoolState,
        viewState: inout PoolDashboardViewState
    ) {
        applyExport(
            snapshot: state.snapshot,
            viewState: &viewState,
            exporter: backupCoordinator.exportSnapshot
        )
    }

    func exportRefetchableSnapshot(
        from state: AccountPoolState,
        viewState: inout PoolDashboardViewState
    ) {
        applyExport(
            snapshot: state.snapshot,
            viewState: &viewState,
            exporter: backupCoordinator.exportRefetchableSnapshot
        )
    }

    func importSnapshot(
        state: inout AccountPoolState,
        viewState: inout PoolDashboardViewState
    ) -> Bool {
        let result = importSnapshotResult(from: viewState.backupJSON)
        return mutationCoordinator.applyBackupImportResult(
            result,
            state: &state,
            viewState: &viewState
        )
    }

    private func applyExport(
        snapshot: AccountPoolSnapshot,
        viewState: inout PoolDashboardViewState,
        exporter: (AccountPoolSnapshot) -> PoolDashboardBackupCoordinator.ExportResult
    ) {
        let result = exporter(snapshot)
        mutationCoordinator.applyBackupExportResult(result, viewState: &viewState)
    }

    private func importSnapshotResult(
        from backupJSON: String
    ) -> PoolDashboardBackupCoordinator.ImportResult {
        backupCoordinator.importSnapshotState(from: backupJSON)
    }

}
