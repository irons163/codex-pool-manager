import Foundation

struct PoolDashboardLocalImportCoordinator {
    struct Output {
        let state: AccountPoolState
        let viewModel: LocalOAuthImportViewModel
        let didImport: Bool
    }

    private let authFlowCoordinator = PoolDashboardAuthFlowCoordinator()

    @MainActor
    func importLocalOAuthAccount(
        _ localAccount: LocalCodexOAuthAccount,
        state: AccountPoolState,
        viewModel: LocalOAuthImportViewModel,
        onRawResponse: @escaping @MainActor (String) -> Void
    ) async -> Output {
        var nextState = state
        var nextViewModel = viewModel

        let existingAccessTokens = Set(nextState.accounts.compactMap(\.apiToken))
        let decision = nextViewModel.prepareImport(
            localAccount,
            existingAccessTokens: existingAccessTokens
        )

        guard case .importAccount = decision else {
            return Output(state: nextState, viewModel: nextViewModel, didImport: false)
        }

        do {
            let context = try await authFlowCoordinator.fetchLocalImportContext(
                decision: decision,
                usageClient: makeUsageClient(onRawResponse: onRawResponse)
            )
            authFlowCoordinator.applyLocalImport(state: &nextState, context: context)
            nextViewModel.errorMessage = nil
            return Output(state: nextState, viewModel: nextViewModel, didImport: true)
        } catch {
            nextViewModel.errorMessage = "無法取得此帳號的即時用量，未匯入：\(authFlowCoordinator.localizedSyncError(error))"
            return Output(state: nextState, viewModel: nextViewModel, didImport: false)
        }
    }

    @MainActor
    private func makeUsageClient(
        onRawResponse: @escaping @MainActor (String) -> Void
    ) -> CodexUsageFetching {
        OpenAICodexUsageClient(
            onRawResponse: { raw in
                Task { @MainActor in
                    onRawResponse(raw)
                }
            }
        )
    }
}
