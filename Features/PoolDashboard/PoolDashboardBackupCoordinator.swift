import Foundation

struct PoolDashboardBackupCoordinator {
    private let dataFlowCoordinator = PoolDashboardDataFlowCoordinator()

    func exportSnapshot(from snapshot: AccountPoolSnapshot) -> (json: String?, errorMessage: String?) {
        do {
            return (try dataFlowCoordinator.exportSnapshotJSON(snapshot), nil)
        } catch {
            return (nil, "匯出失敗：\(error.localizedDescription)")
        }
    }

    func exportRefetchableSnapshot(from snapshot: AccountPoolSnapshot) -> (json: String?, errorMessage: String?) {
        do {
            return (try dataFlowCoordinator.exportRefetchableSnapshotJSON(snapshot), nil)
        } catch {
            return (nil, "匯出失敗：\(error.localizedDescription)")
        }
    }

    func importSnapshotState(from json: String) -> (state: AccountPoolState?, errorMessage: String?) {
        do {
            return (try dataFlowCoordinator.importState(from: json), nil)
        } catch {
            return (nil, "匯入失敗：\(error.localizedDescription)")
        }
    }
}
