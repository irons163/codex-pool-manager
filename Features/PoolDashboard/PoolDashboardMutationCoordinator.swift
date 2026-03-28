import Foundation

struct PoolDashboardMutationCoordinator {
    func applyBackupExportResult(
        _ result: PoolDashboardBackupCoordinator.ExportResult,
        viewState: inout PoolDashboardViewState
    ) {
        switch (result.json, result.errorMessage) {
        case let (json?, _):
            viewState.backupJSON = json
            viewState.backupError = nil
        case let (_, message?):
            viewState.backupJSON = ""
            viewState.backupError = message
        case (nil, nil):
            break
        }
    }

    func applyBackupImportResult(
        _ result: PoolDashboardBackupCoordinator.ImportResult,
        state: inout AccountPoolState,
        viewState: inout PoolDashboardViewState
    ) -> Bool {
        switch (result.state, result.errorMessage) {
        case let (importedState?, _):
            state = importedState
            viewState.backupError = nil
            return true
        case let (_, message?):
            viewState.backupError = message
            return false
        case (nil, nil):
            return false
        }
    }

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
        if output.didSwitchAuth {
            viewState.switchLaunchError = nil
            viewState.switchLaunchWarning = output.errorMessage == nil ? nil : L10n.text("switch.warning.launch_failed_but_switched")
        } else {
            viewState.switchLaunchError = output.errorMessage
            viewState.switchLaunchWarning = nil
        }
        viewModel.errorMessage = nil
        sessionAuthorizedAuthFileURL = output.sessionAuthorizedAuthFileURL
    }
}
