import Foundation

struct PoolDashboardMutationCoordinator {
    func applySyncOutput(
        _ output: PoolDashboardRuntimeCoordinator.SyncOutput,
        state: inout AccountPoolState,
        lastUsageRawJSON: inout String,
        syncError: inout String?
    ) {
        state = output.state
        if let rawResponse = output.lastUsageRawJSON {
            lastUsageRawJSON = rawResponse
        }
        syncError = output.syncError
    }

    func applyOAuthOutput(
        _ output: PoolDashboardRuntimeCoordinator.OAuthSignInOutput,
        state: inout AccountPoolState,
        oauthError: inout String?,
        oauthSuccessMessage: inout String?,
        oauthAccountName: inout String
    ) -> Bool {
        state = output.state
        oauthError = output.oauthError
        oauthSuccessMessage = output.oauthSuccessMessage
        oauthAccountName = output.nextOAuthAccountName
        return output.shouldRefreshLocalOAuthAccounts
    }

    func applyLocalImportOutput(
        _ output: PoolDashboardLocalImportCoordinator.Output,
        state: inout AccountPoolState,
        viewModel: inout LocalOAuthImportViewModel,
        syncError: inout String?
    ) {
        state = output.state
        viewModel = output.viewModel
        if output.didImport {
            syncError = nil
        }
    }

    func applySwitchOutput(
        _ output: PoolDashboardSwitchLaunchCoordinator.Output,
        viewModel: inout LocalOAuthImportViewModel,
        lastSwitchLaunchLog: inout String,
        sessionAuthorizedAuthFileURL: inout URL?
    ) {
        lastSwitchLaunchLog = output.switchLaunchLog
        viewModel.errorMessage = output.errorMessage
        sessionAuthorizedAuthFileURL = output.sessionAuthorizedAuthFileURL
    }
}
