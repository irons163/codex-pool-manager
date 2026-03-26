import Foundation

struct PoolDashboardLifecycleFlowCoordinator {
    struct OnAppearOutput {
        let state: AccountPoolState
        let lowUsageAlertPolicy: LowUsageAlertPolicy
        let viewModel: LocalOAuthImportViewModel
        let sessionAuthorizedAuthFileURL: URL?
    }

    struct SnapshotChangeOutput {
        let lowUsageAlertPolicy: LowUsageAlertPolicy
        let viewState: PoolDashboardViewState
    }

    private let lifecycleCoordinator = PoolDashboardLifecycleCoordinator()
    private let localAccountsFlowCoordinator = PoolDashboardLocalAccountsFlowCoordinator()

    func onAppear(
        state: AccountPoolState,
        lowUsageAlertPolicy: LowUsageAlertPolicy,
        viewModel: LocalOAuthImportViewModel,
        authFileAccessService: CodexAuthFileAccessService,
        currentAuthorizedAuthFileURL: URL?
    ) -> OnAppearOutput {
        var nextState = state
        var nextLowUsageAlertPolicy = lowUsageAlertPolicy
        lifecycleCoordinator.onAppear(
            state: &nextState,
            lowUsageAlertPolicy: &nextLowUsageAlertPolicy
        )

        let localAccountsOutput = localAccountsFlowCoordinator.refreshLocalOAuthAccounts(
            from: nextState,
            viewModel: viewModel,
            authFileAccessService: authFileAccessService,
            currentAuthorizedAuthFileURL: currentAuthorizedAuthFileURL
        )

        return OnAppearOutput(
            state: localAccountsOutput.state,
            lowUsageAlertPolicy: nextLowUsageAlertPolicy,
            viewModel: localAccountsOutput.viewModel,
            sessionAuthorizedAuthFileURL: localAccountsOutput.sessionAuthorizedAuthFileURL
        )
    }

    func onSnapshotChanged(
        snapshot: AccountPoolSnapshot,
        state: AccountPoolState,
        lowUsageAlertPolicy: LowUsageAlertPolicy,
        viewState: PoolDashboardViewState,
        store: AccountPoolStoring
    ) -> SnapshotChangeOutput {
        store.save(snapshot)

        var nextLowUsageAlertPolicy = lowUsageAlertPolicy
        var nextViewState = viewState
        if lifecycleCoordinator.shouldShowLowUsageAlert(
            state: state,
            lowUsageAlertPolicy: &nextLowUsageAlertPolicy
        ) {
            nextViewState.showLowUsageAlert = true
        }

        return SnapshotChangeOutput(
            lowUsageAlertPolicy: nextLowUsageAlertPolicy,
            viewState: nextViewState
        )
    }
}
