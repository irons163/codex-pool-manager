import Foundation

struct PoolDashboardBackupCoordinator {
    private enum Message {
        static var exportFailurePrefix: String { L10n.text("backup.operation.export_failed") }
        static var importFailurePrefix: String { L10n.text("backup.operation.import_failed") }
    }

    typealias ExportResult = (json: String?, errorMessage: String?)
    typealias ImportResult = (state: AccountPoolState?, errorMessage: String?)

    private let dataFlowCoordinator = PoolDashboardDataFlowCoordinator()

    func exportSnapshot(from snapshot: AccountPoolSnapshot) -> ExportResult {
        runOperation(failurePrefix: Message.exportFailurePrefix) {
            try dataFlowCoordinator.exportSnapshotJSON(snapshot)
        }
    }

    func exportRefetchableSnapshot(from snapshot: AccountPoolSnapshot) -> ExportResult {
        runOperation(failurePrefix: Message.exportFailurePrefix) {
            try dataFlowCoordinator.exportRefetchableSnapshotJSON(snapshot)
        }
    }

    func importSnapshotState(from json: String) -> ImportResult {
        runOperation(failurePrefix: Message.importFailurePrefix) {
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
            return (nil, L10n.text("backup.operation.error_format", failurePrefix, error.localizedDescription))
        }
    }
}
