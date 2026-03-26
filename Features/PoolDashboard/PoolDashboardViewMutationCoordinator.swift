import Foundation

struct PoolDashboardViewMutationCoordinator {
    func applyLifecycleOnAppearOutput(
        _ output: PoolDashboardLifecycleFlowCoordinator.OnAppearOutput,
        state: inout AccountPoolState,
        lowUsageAlertPolicy: inout LowUsageAlertPolicy,
        viewModel: inout LocalOAuthImportViewModel,
        sessionAuthorizedAuthFileURL: inout URL?
    ) {
        state = output.state
        viewModel = output.viewModel
        sessionAuthorizedAuthFileURL = output.sessionAuthorizedAuthFileURL
        lowUsageAlertPolicy = output.lowUsageAlertPolicy
    }

    func applyLifecycleSnapshotChangeOutput(
        _ output: PoolDashboardLifecycleFlowCoordinator.SnapshotChangeOutput,
        lowUsageAlertPolicy: inout LowUsageAlertPolicy,
        viewState: inout PoolDashboardViewState
    ) {
        lowUsageAlertPolicy = output.lowUsageAlertPolicy
        viewState = output.viewState
    }

    func applyUsageSyncOutput(
        _ output: PoolDashboardUsageSyncFlowCoordinator.Output,
        state: inout AccountPoolState,
        viewState: inout PoolDashboardViewState
    ) {
        state = output.state
        viewState = output.viewState
    }

    func applyOAuthSignInOutput(
        _ output: PoolDashboardOAuthSignInFlowCoordinator.Output,
        state: inout AccountPoolState,
        viewState: inout PoolDashboardViewState,
        formState: inout PoolDashboardFormState
    ) {
        state = output.state
        viewState = output.viewState
        formState.applyOAuthAccountName(output.oauthAccountName)
    }

    func applyLocalAccountsOutput(
        _ output: PoolDashboardLocalAccountsFlowCoordinator.Output,
        state: inout AccountPoolState,
        viewModel: inout LocalOAuthImportViewModel,
        sessionAuthorizedAuthFileURL: inout URL?
    ) -> URL? {
        state = output.state
        viewModel = output.viewModel
        sessionAuthorizedAuthFileURL = output.sessionAuthorizedAuthFileURL
        return output.pickedAuthFileURL
    }

    func applyLocalImportOutput(
        _ output: PoolDashboardLocalImportFlowCoordinator.Output,
        state: inout AccountPoolState,
        viewModel: inout LocalOAuthImportViewModel,
        viewState: inout PoolDashboardViewState
    ) {
        state = output.state
        viewState = output.viewState
        viewModel = output.viewModel
    }

    func applySwitchLaunchOutput(
        _ output: PoolDashboardSwitchLaunchFlowCoordinator.Output,
        viewModel: inout LocalOAuthImportViewModel,
        viewState: inout PoolDashboardViewState,
        sessionAuthorizedAuthFileURL: inout URL?
    ) {
        viewModel = output.viewModel
        viewState = output.viewState
        sessionAuthorizedAuthFileURL = output.sessionAuthorizedAuthFileURL
    }
}
