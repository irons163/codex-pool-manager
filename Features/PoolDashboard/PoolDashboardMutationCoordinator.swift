import Foundation

struct PoolDashboardMutationCoordinator {
    func applySyncOutput(
        _ output: PoolDashboardRuntimeCoordinator.SyncOutput,
        state: inout AccountPoolState,
        viewState: inout PoolDashboardViewState
    ) {
        state = output.state
        if let rawResponse = output.lastUsageRawJSON {
            viewState.lastUsageRawJSON = rawResponse
        }
        viewState.syncError = output.syncError
    }

    func applyOAuthOutput(
        _ output: PoolDashboardRuntimeCoordinator.OAuthSignInOutput,
        state: inout AccountPoolState,
        viewState: inout PoolDashboardViewState,
        oauthAccountName: inout String
    ) -> Bool {
        state = output.state
        viewState.oauthError = output.oauthError
        viewState.oauthSuccessMessage = output.oauthSuccessMessage
        oauthAccountName = output.nextOAuthAccountName
        return output.shouldRefreshLocalOAuthAccounts
    }

    func applyLocalImportOutput(
        _ output: PoolDashboardLocalImportCoordinator.Output,
        state: inout AccountPoolState,
        viewModel: inout LocalOAuthImportViewModel,
        viewState: inout PoolDashboardViewState
    ) {
        state = output.state
        viewModel = output.viewModel
        if output.didImport {
            viewState.syncError = nil
        }
    }

    func applySwitchOutput(
        _ output: PoolDashboardSwitchLaunchCoordinator.Output,
        viewModel: inout LocalOAuthImportViewModel,
        viewState: inout PoolDashboardViewState,
        sessionAuthorizedAuthFileURL: inout URL?
    ) {
        viewState.lastSwitchLaunchLog = output.switchLaunchLog
        viewModel.errorMessage = output.errorMessage
        sessionAuthorizedAuthFileURL = output.sessionAuthorizedAuthFileURL
    }
}
