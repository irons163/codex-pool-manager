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

        return makeOnAppearOutput(
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
        applyLowUsageAlertIfNeeded(
            state: state,
            lowUsageAlertPolicy: &nextLowUsageAlertPolicy,
            viewState: &nextViewState
        )

        return makeSnapshotChangeOutput(
            lowUsageAlertPolicy: nextLowUsageAlertPolicy,
            viewState: nextViewState
        )
    }

    private func makeOnAppearOutput(
        state: AccountPoolState,
        lowUsageAlertPolicy: LowUsageAlertPolicy,
        viewModel: LocalOAuthImportViewModel,
        sessionAuthorizedAuthFileURL: URL?
    ) -> OnAppearOutput {
        OnAppearOutput(
            state: state,
            lowUsageAlertPolicy: lowUsageAlertPolicy,
            viewModel: viewModel,
            sessionAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL
        )
    }

    private func makeSnapshotChangeOutput(
        lowUsageAlertPolicy: LowUsageAlertPolicy,
        viewState: PoolDashboardViewState
    ) -> SnapshotChangeOutput {
        SnapshotChangeOutput(
            lowUsageAlertPolicy: lowUsageAlertPolicy,
            viewState: viewState
        )
    }

    private func applyLowUsageAlertIfNeeded(
        state: AccountPoolState,
        lowUsageAlertPolicy: inout LowUsageAlertPolicy,
        viewState: inout PoolDashboardViewState
    ) {
        if lifecycleCoordinator.shouldShowLowUsageAlert(
            state: state,
            lowUsageAlertPolicy: &lowUsageAlertPolicy
        ) {
            viewState.showLowUsageAlert = true
        }
    }
}
