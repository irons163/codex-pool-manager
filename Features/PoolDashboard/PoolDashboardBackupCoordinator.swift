import Foundation

struct PoolDashboardBackupCoordinator {
    private let dataFlowCoordinator = PoolDashboardDataFlowCoordinator()

    func exportSnapshot(from snapshot: AccountPoolSnapshot) -> (json: String?, errorMessage: String?) {
        export {
            try dataFlowCoordinator.exportSnapshotJSON(snapshot)
        }
    }

    func exportRefetchableSnapshot(from snapshot: AccountPoolSnapshot) -> (json: String?, errorMessage: String?) {
        export {
            try dataFlowCoordinator.exportRefetchableSnapshotJSON(snapshot)
        }
    }

    func importSnapshotState(from json: String) -> (state: AccountPoolState?, errorMessage: String?) {
        `import` {
            try dataFlowCoordinator.importState(from: json)
        }
    }

    private func `import`(
        _ operation: () throws -> AccountPoolState
    ) -> (state: AccountPoolState?, errorMessage: String?) {
        do {
            return (try operation(), nil)
        } catch {
            return (nil, "匯入失敗：\(error.localizedDescription)")
        }
    }

    private func export(
        _ operation: () throws -> String
    ) -> (json: String?, errorMessage: String?) {
        do {
            return (try operation(), nil)
        } catch {
            return (nil, "匯出失敗：\(error.localizedDescription)")
        }
    }
}
