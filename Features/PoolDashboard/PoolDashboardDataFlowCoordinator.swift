import Foundation

struct PoolDashboardDataFlowCoordinator {
    func exportSnapshotJSON(_ snapshot: AccountPoolSnapshot) throws -> String {
        try exportSnapshotJSON(snapshot, redactSensitive: true)
    }

    func exportRefetchableSnapshotJSON(_ snapshot: AccountPoolSnapshot) throws -> String {
        try exportSnapshotJSON(snapshot, redactSensitive: false)
    }

    func importState(from json: String) throws -> AccountPoolState {
        let snapshot = try AccountPoolSnapshotCodec.importJSON(json)
        return AccountPoolState(snapshot: snapshot)
    }

    func syncState(
        from state: AccountPoolState
    ) async throws -> (state: AccountPoolState, rawResponse: String?) {
        var capturedRaw: String?
        let client = OpenAICodexUsageClient { raw in
            capturedRaw = raw
        }
        let service = CodexUsageSyncService(client: client)
        var nextState = state
        try await service.sync(state: &nextState)
        return (nextState, capturedRaw)
    }

    private func exportSnapshotJSON(
        _ snapshot: AccountPoolSnapshot,
        redactSensitive: Bool
    ) throws -> String {
        try AccountPoolSnapshotCodec.exportJSON(snapshot, redactSensitive: redactSensitive)
    }
}
