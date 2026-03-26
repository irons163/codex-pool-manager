import Foundation

struct PoolDashboardViewMutationCoordinator {
    func applyLifecycleOnAppearOutput(
        _ output: PoolDashboardLifecycleFlowCoordinator.OnAppearOutput,
        state: inout AccountPoolState,
        lowUsageAlertPolicy: inout LowUsageAlertPolicy,
        viewModel: inout LocalOAuthImportViewModel,
        sessionAuthorizedAuthFileURL: inout URL?
    ) {
        assign(
            state: output.state,
            viewModel: output.viewModel,
            sessionAuthorizedAuthFileURL: output.sessionAuthorizedAuthFileURL,
            to: &state,
            viewModel: &viewModel,
            sessionAuthorizedAuthFileURL: &sessionAuthorizedAuthFileURL
        )
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
        assign(
            state: output.state,
            viewState: output.viewState,
            to: &state,
            and: &viewState
        )
    }

    func applyOAuthSignInOutput(
        _ output: PoolDashboardOAuthSignInFlowCoordinator.Output,
        state: inout AccountPoolState,
        viewState: inout PoolDashboardViewState,
        formState: inout PoolDashboardFormState
    ) {
        assign(
            state: output.state,
            viewState: output.viewState,
            to: &state,
            and: &viewState
        )
        formState.applyOAuthAccountName(output.oauthAccountName)
    }

    func applyLocalAccountsOutput(
        _ output: PoolDashboardLocalAccountsFlowCoordinator.Output,
        state: inout AccountPoolState,
        viewModel: inout LocalOAuthImportViewModel,
        sessionAuthorizedAuthFileURL: inout URL?
    ) -> URL? {
        assign(
            state: output.state,
            viewModel: output.viewModel,
            sessionAuthorizedAuthFileURL: output.sessionAuthorizedAuthFileURL,
            to: &state,
            viewModel: &viewModel,
            sessionAuthorizedAuthFileURL: &sessionAuthorizedAuthFileURL
        )
        return output.pickedAuthFileURL
    }

    func applyLocalImportOutput(
        _ output: PoolDashboardLocalImportFlowCoordinator.Output,
        state: inout AccountPoolState,
        viewModel: inout LocalOAuthImportViewModel,
        viewState: inout PoolDashboardViewState
    ) {
        assign(
            state: output.state,
            viewState: output.viewState,
            to: &state,
            and: &viewState
        )
        viewModel = output.viewModel
    }

    func applySwitchLaunchOutput(
        _ output: PoolDashboardSwitchLaunchFlowCoordinator.Output,
        viewModel: inout LocalOAuthImportViewModel,
        viewState: inout PoolDashboardViewState,
        sessionAuthorizedAuthFileURL: inout URL?
    ) {
        assign(
            viewModel: output.viewModel,
            viewState: output.viewState,
            sessionAuthorizedAuthFileURL: output.sessionAuthorizedAuthFileURL,
            to: &viewModel,
            and: &viewState,
            sessionAuthorizedAuthFileURL: &sessionAuthorizedAuthFileURL
        )
    }

    private func assign(
        state: AccountPoolState,
        viewState: PoolDashboardViewState,
        to currentState: inout AccountPoolState,
        and currentViewState: inout PoolDashboardViewState
    ) {
        currentState = state
        currentViewState = viewState
    }

    private func assign(
        state: AccountPoolState,
        viewModel: LocalOAuthImportViewModel,
        sessionAuthorizedAuthFileURL: URL?,
        to currentState: inout AccountPoolState,
        viewModel currentViewModel: inout LocalOAuthImportViewModel,
        sessionAuthorizedAuthFileURL currentSessionAuthorizedAuthFileURL: inout URL?
    ) {
        currentState = state
        currentViewModel = viewModel
        currentSessionAuthorizedAuthFileURL = sessionAuthorizedAuthFileURL
    }

    private func assign(
        viewModel: LocalOAuthImportViewModel,
        viewState: PoolDashboardViewState,
        sessionAuthorizedAuthFileURL: URL?,
        to currentViewModel: inout LocalOAuthImportViewModel,
        and currentViewState: inout PoolDashboardViewState,
        sessionAuthorizedAuthFileURL currentSessionAuthorizedAuthFileURL: inout URL?
    ) {
        currentViewModel = viewModel
        currentViewState = viewState
        currentSessionAuthorizedAuthFileURL = sessionAuthorizedAuthFileURL
    }
}
