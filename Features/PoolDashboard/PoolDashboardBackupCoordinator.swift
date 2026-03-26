import Foundation

struct PoolDashboardBackupCoordinator {
    typealias ExportResult = (json: String?, errorMessage: String?)
    typealias ImportResult = (state: AccountPoolState?, errorMessage: String?)

    private let dataFlowCoordinator = PoolDashboardDataFlowCoordinator()

    func exportSnapshot(from snapshot: AccountPoolSnapshot) -> ExportResult {
        export {
            try dataFlowCoordinator.exportSnapshotJSON(snapshot)
        }
    }

    func exportRefetchableSnapshot(from snapshot: AccountPoolSnapshot) -> ExportResult {
        export {
            try dataFlowCoordinator.exportRefetchableSnapshotJSON(snapshot)
        }
    }

    func importSnapshotState(from json: String) -> ImportResult {
        importSnapshot {
            try dataFlowCoordinator.importState(from: json)
        }
    }

    private func importSnapshot(
        _ operation: () throws -> AccountPoolState
    ) -> ImportResult {
        do {
            return (try operation(), nil)
        } catch {
            return (nil, "匯入失敗：\(error.localizedDescription)")
        }
    }

    private func export(
        _ operation: () throws -> String
    ) -> ExportResult {
        do {
            return (try operation(), nil)
        } catch {
            return (nil, "匯出失敗：\(error.localizedDescription)")
        }
    }
}
