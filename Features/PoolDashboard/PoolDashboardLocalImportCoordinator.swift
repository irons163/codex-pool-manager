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

        let decision = nextViewModel.prepareImport(
            localAccount,
            existingAccessTokens: Set(nextState.accounts.compactMap(\.apiToken))
        )

        guard case .importAccount = decision else {
            return Output(state: nextState, viewModel: nextViewModel, didImport: false)
        }

        do {
            let context = try await authFlowCoordinator.fetchLocalImportContext(
                decision: decision,
                usageClient: OpenAICodexUsageClient(
                    onRawResponse: { raw in
                        Task { @MainActor in
                            onRawResponse(raw)
                        }
                    }
                )
            )
            authFlowCoordinator.applyLocalImport(state: &nextState, context: context)
            nextViewModel.errorMessage = nil
            return Output(state: nextState, viewModel: nextViewModel, didImport: true)
        } catch {
            let syncErrorMessage = authFlowCoordinator.localizedSyncError(error)
            nextViewModel.errorMessage = "無法取得此帳號的即時用量，未匯入：\(syncErrorMessage)"
            return Output(state: nextState, viewModel: nextViewModel, didImport: false)
        }
    }
}
