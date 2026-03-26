import Foundation

struct PoolDashboardDataFlowCoordinator {
    func exportSnapshotJSON(_ snapshot: AccountPoolSnapshot) throws -> String {
        try export(snapshot, redactSensitive: true)
    }

    func exportRefetchableSnapshotJSON(_ snapshot: AccountPoolSnapshot) throws -> String {
        try export(snapshot, redactSensitive: false)
    }

    func importState(from json: String) throws -> AccountPoolState {
        let snapshot = try AccountPoolSnapshotCodec.importJSON(json)
        return AccountPoolState(snapshot: snapshot)
    }

    func syncState(
        from state: AccountPoolState
    ) async throws -> (state: AccountPoolState, rawResponse: String?) {
        var capturedRaw: String?
        let client = makeUsageClient { raw in
            capturedRaw = raw
        }
        let service = makeUsageSyncService(client: client)
        var nextState = state
        try await service.sync(state: &nextState)
        return (nextState, capturedRaw)
    }

    private func export(
        _ snapshot: AccountPoolSnapshot,
        redactSensitive: Bool
    ) throws -> String {
        try AccountPoolSnapshotCodec.exportJSON(snapshot, redactSensitive: redactSensitive)
    }

    private func makeUsageClient(onRawResponse: @escaping (String) -> Void) -> OpenAICodexUsageClient {
        OpenAICodexUsageClient(onRawResponse: onRawResponse)
    }

    private func makeUsageSyncService(
        client: OpenAICodexUsageClient
    ) -> CodexUsageSyncService<OpenAICodexUsageClient> {
        CodexUsageSyncService(client: client)
    }
}
