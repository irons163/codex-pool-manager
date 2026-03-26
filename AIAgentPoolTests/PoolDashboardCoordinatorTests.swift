import Foundation
import Testing
@testable import AIAgentPool

struct PoolDashboardAsyncStateCoordinatorTests {
    @Test
    func poolDashboardAsyncStateCoordinatorBeginUsageSyncGuardsConcurrentRuns() {
        let coordinator = PoolDashboardAsyncStateCoordinator()
        var viewState = PoolDashboardViewState()

        let first = coordinator.beginUsageSync(viewState: &viewState)
        let second = coordinator.beginUsageSync(viewState: &viewState)

        #expect(first)
        #expect(!second)
        #expect(viewState.isSyncingUsage)
    }

    @Test
    func poolDashboardAsyncStateCoordinatorEndUsageSyncResetsFlag() {
        let coordinator = PoolDashboardAsyncStateCoordinator()
        var viewState = PoolDashboardViewState()
        _ = coordinator.beginUsageSync(viewState: &viewState)

        coordinator.endUsageSync(viewState: &viewState)

        #expect(!viewState.isSyncingUsage)
    }

    @Test
    func poolDashboardAsyncStateCoordinatorBeginAndEndOAuthSignInManagesFlagsAndMessages() {
        let coordinator = PoolDashboardAsyncStateCoordinator()
        var viewState = PoolDashboardViewState()
        viewState.oauthError = "old-error"
        viewState.oauthSuccessMessage = "old-success"

        let first = coordinator.beginOAuthSignIn(viewState: &viewState)
        let second = coordinator.beginOAuthSignIn(viewState: &viewState)
        coordinator.endOAuthSignIn(viewState: &viewState)

        #expect(first)
        #expect(!second)
        #expect(viewState.oauthError == nil)
        #expect(viewState.oauthSuccessMessage == nil)
        #expect(!viewState.isSigningInOAuth)
    }

}

@MainActor
struct PoolDashboardViewMutationCoordinatorTests {
    @Test
    func poolDashboardViewMutationCoordinatorApplyLifecycleOnAppearOutputUpdatesAllTargets() {
        var state = AccountPoolState(accounts: [], mode: .manual)
        var policy = LowUsageAlertPolicy()
        var viewModel = LocalOAuthImportViewModel()
        var sessionURL: URL? = nil
        let expectedURL = URL(string: "file:///tmp/auth.json")
        var nextState = AccountPoolState(
            accounts: [AgentAccount(id: UUID(), name: "A", usedUnits: 1, quota: 10)],
            mode: .focus
        )
        nextState.evaluate()
        var nextPolicy = LowUsageAlertPolicy()
        _ = nextPolicy.shouldTriggerAlert(mode: .focus, hasLowUsageWarning: true)
        let output = PoolDashboardLifecycleFlowCoordinator.OnAppearOutput(
            state: nextState,
            lowUsageAlertPolicy: nextPolicy,
            viewModel: LocalOAuthImportViewModel(),
            sessionAuthorizedAuthFileURL: expectedURL
        )
        let coordinator = PoolDashboardViewMutationCoordinator()

        coordinator.applyLifecycleOnAppearOutput(
            output,
            state: &state,
            lowUsageAlertPolicy: &policy,
            viewModel: &viewModel,
            sessionAuthorizedAuthFileURL: &sessionURL
        )

        #expect(state.snapshot == nextState.snapshot)
        #expect(!policy.shouldTriggerAlert(mode: .focus, hasLowUsageWarning: true))
        #expect(viewModel.accounts.isEmpty)
        #expect(sessionURL == expectedURL)
    }

    @Test
    func poolDashboardViewMutationCoordinatorApplyLocalAccountsOutputReturnsPickedURL() {
        var state = AccountPoolState(accounts: [], mode: .manual)
        var viewModel = LocalOAuthImportViewModel()
        var sessionURL: URL? = nil
        let expectedSessionURL = URL(string: "file:///tmp/session.json")
        let expectedPickedURL = URL(string: "file:///tmp/picked.json")
        let output = PoolDashboardLocalAccountsFlowCoordinator.Output(
            state: AccountPoolState(
                accounts: [AgentAccount(id: UUID(), name: "Imported", usedUnits: 0, quota: 100)],
                mode: .manual
            ),
            viewModel: LocalOAuthImportViewModel(),
            sessionAuthorizedAuthFileURL: expectedSessionURL,
            pickedAuthFileURL: expectedPickedURL
        )
        let coordinator = PoolDashboardViewMutationCoordinator()

        let pickedURL = coordinator.applyLocalAccountsOutput(
            output,
            state: &state,
            viewModel: &viewModel,
            sessionAuthorizedAuthFileURL: &sessionURL
        )

        #expect(state.accounts.count == 1)
        #expect(state.accounts[0].name == "Imported")
        #expect(sessionURL == expectedSessionURL)
        #expect(pickedURL == expectedPickedURL)
    }

    @Test
    func poolDashboardViewMutationCoordinatorApplySwitchLaunchOutputUpdatesAllTargets() {
        var viewModel = LocalOAuthImportViewModel()
        var viewState = PoolDashboardViewState()
        var sessionURL: URL? = nil
        let expectedSessionURL = URL(string: "file:///tmp/next.json")
        var nextViewState = PoolDashboardViewState()
        nextViewState.lastSwitchLaunchLog = "log-line"
        let output = PoolDashboardSwitchLaunchFlowCoordinator.Output(
            viewModel: LocalOAuthImportViewModel(),
            viewState: nextViewState,
            sessionAuthorizedAuthFileURL: expectedSessionURL
        )
        let coordinator = PoolDashboardViewMutationCoordinator()

        coordinator.applySwitchLaunchOutput(
            output,
            viewModel: &viewModel,
            viewState: &viewState,
            sessionAuthorizedAuthFileURL: &sessionURL
        )

        #expect(viewModel.accounts.isEmpty)
        #expect(viewState.lastSwitchLaunchLog == "log-line")
        #expect(sessionURL == expectedSessionURL)
    }
}
