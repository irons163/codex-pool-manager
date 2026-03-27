import Foundation

struct PoolDashboardBackupCoordinator {
    typealias ExportResult = (json: String?, errorMessage: String?)
    typealias ImportResult = (state: AccountPoolState?, errorMessage: String?)

    private let dataFlowCoordinator = PoolDashboardDataFlowCoordinator()

    func exportSnapshot(from snapshot: AccountPoolSnapshot) -> ExportResult {
        runOperation(failurePrefix: "匯出失敗") {
            try dataFlowCoordinator.exportSnapshotJSON(snapshot)
        }
    }

    func exportRefetchableSnapshot(from snapshot: AccountPoolSnapshot) -> ExportResult {
        runOperation(failurePrefix: "匯出失敗") {
            try dataFlowCoordinator.exportRefetchableSnapshotJSON(snapshot)
        }
    }

    func importSnapshotState(from json: String) -> ImportResult {
        runOperation(failurePrefix: "匯入失敗") {
            try dataFlowCoordinator.importState(from: json)
        }
    }

    private func runOperation<Result>(
        failurePrefix: String,
        _ operation: () throws -> Result
    ) -> (Result?, String?) {
        do {
            return (try operation(), nil)
        } catch {
            return (nil, "\(failurePrefix)：\(error.localizedDescription)")
        }
    }
}
