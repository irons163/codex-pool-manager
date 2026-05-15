import Foundation
import Testing
@testable import CodexPoolManager

struct PoolDashboardAsyncStateCoordinatorTests {
    @Test
    func poolDashboardAsyncStateCoordinatorBeginUsageSyncGuardsConcurrentRuns() {
        let coordinator = PoolDashboardAsyncStateCoordinator()
        var viewState = PoolDashboardViewState()
        viewState.syncError = "old-error"

        let first = coordinator.beginUsageSync(viewState: &viewState)
        let second = coordinator.beginUsageSync(viewState: &viewState)

        #expect(first)
        #expect(!second)
        #expect(viewState.isSyncingUsage)
        #expect(viewState.usageSyncStartedAt != nil)
        #expect(viewState.syncError == nil)
    }

    @Test
    func poolDashboardAsyncStateCoordinatorEndUsageSyncResetsFlag() {
        let coordinator = PoolDashboardAsyncStateCoordinator()
        var viewState = PoolDashboardViewState()
        _ = coordinator.beginUsageSync(viewState: &viewState)

        coordinator.endUsageSync(viewState: &viewState)

        #expect(!viewState.isSyncingUsage)
        #expect(viewState.usageSyncStartedAt == nil)
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
struct PoolDashboardSwitchLaunchCoordinatorTests {
    @Test
    func poolDashboardSwitchLaunchCoordinatorDoesNotTreatInvalidBookmarkAsMissingAuthFile() async {
        let coordinator = PoolDashboardSwitchLaunchCoordinator()
        let bookmarkKey = "test.invalid.bookmark.\(UUID().uuidString)"
        UserDefaults.standard.set(Data("invalid-bookmark".utf8), forKey: bookmarkKey)
        defer { UserDefaults.standard.removeObject(forKey: bookmarkKey) }

        let account = AgentAccount(
            id: UUID(),
            name: "Valid",
            usedUnits: 0,
            quota: 100,
            apiToken: "token",
            chatGPTAccountID: "acct_1"
        )
        var authorizeCalled = false

        let output = await coordinator.switchAndLaunch(
            account: account,
            currentAuthorizedAuthFileURL: nil,
            authFileAccessService: CodexAuthFileAccessService(bookmarkKey: bookmarkKey),
            authorizeAuthFile: {
                authorizeCalled = true
                return nil
            }
        )

        #expect(!authorizeCalled)
        #expect(output.errorMessage?.hasPrefix("\(L10n.text("switch.error.prefix")):") == true)
        #expect(output.switchLaunchLog.contains("\(L10n.text("switch.log.error_prefix")):"))
        #expect(!output.switchLaunchLog.contains(L10n.text("switch.log.auth_permission_start")))
    }
}

@MainActor
struct PoolDashboardViewMutationCoordinatorTests {
    @Test
    func poolDashboardViewMutationCoordinatorApplyUsageSyncOutputMergesWithoutRevertingConcurrentChanges() {
        let accountAID = UUID()
        let accountBID = UUID()
        var state = AccountPoolState(
            accounts: [
                AgentAccount(
                    id: accountAID,
                    name: "Edited Name",
                    groupName: "Runtime",
                    usedUnits: 10,
                    quota: 100,
                    apiToken: "token-a"
                ),
                AgentAccount(
                    id: accountBID,
                    name: "New During Sync",
                    usedUnits: 5,
                    quota: 50,
                    apiToken: "token-b"
                )
            ],
            mode: .focus
        )
        state.setMode(.focus)

        var viewState = PoolDashboardViewState()
        viewState.oauthSuccessMessage = "keep-this-message"

        var syncedState = AccountPoolState(
            accounts: [
                AgentAccount(
                    id: accountAID,
                    name: "Old Name",
                    groupName: "Default",
                    usedUnits: 70,
                    quota: 200,
                    apiToken: "old-token",
                    usageWindowName: "weekly_window",
                    usageWindowResetAt: Date(timeIntervalSince1970: 1_700_000_000),
                    primaryUsagePercent: 33,
                    primaryUsageResetAt: Date(timeIntervalSince1970: 1_700_000_123),
                    secondaryUsagePercent: 70,
                    secondaryUsageResetAt: Date(timeIntervalSince1970: 1_700_000_456),
                    isPaid: true,
                    isUsageSyncExcluded: true,
                    usageSyncError: "sync failed"
                )
            ],
            mode: .intelligent
        )
        let syncedAt = Date(timeIntervalSince1970: 1_700_000_789)
        syncedState.markUsageSynced(at: syncedAt)

        var syncedViewState = PoolDashboardViewState()
        syncedViewState.syncError = "sync-timeout"
        syncedViewState.lastUsageRawJSON = "{\"ok\":true}"

        let output = PoolDashboardUsageSyncFlowCoordinator.Output(
            state: syncedState,
            viewState: syncedViewState
        )
        let coordinator = PoolDashboardViewMutationCoordinator()

        coordinator.applyUsageSyncOutput(
            output,
            state: &state,
            viewState: &viewState
        )

        let updatedA = state.accounts.first(where: { $0.id == accountAID })
        let preservedB = state.accounts.first(where: { $0.id == accountBID })

        #expect(state.mode == .focus)
        #expect(updatedA?.name == "Edited Name")
        #expect(updatedA?.groupName == "Runtime")
        #expect(updatedA?.usedUnits == 70)
        #expect(updatedA?.quota == 200)
        #expect(updatedA?.usageWindowName == "weekly_window")
        #expect(updatedA?.primaryUsagePercent == 33)
        #expect(updatedA?.secondaryUsagePercent == 70)
        #expect(updatedA?.isPaid == true)
        #expect(updatedA?.isUsageSyncExcluded == true)
        #expect(updatedA?.usageSyncError == "sync failed")
        #expect(preservedB?.name == "New During Sync")
        #expect(state.lastUsageSyncAt == syncedAt)

        #expect(viewState.oauthSuccessMessage == "keep-this-message")
        #expect(viewState.syncError == "sync-timeout")
        #expect(viewState.lastUsageRawJSON == "{\"ok\":true}")
    }

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
        let shouldTriggerAgain = policy.shouldTriggerAlert(mode: .focus, hasLowUsageWarning: true)
        #expect(!shouldTriggerAgain)
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
            sessionAuthorizedAuthFileURL: expectedSessionURL,
            didSwitchAuth: false
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

    @Test
    func poolDashboardViewMutationCoordinatorApplyOAuthSignInOutputUpdatesFormStateName() {
        var state = AccountPoolState(accounts: [], mode: .manual)
        var viewState = PoolDashboardViewState()
        var formState = PoolDashboardFormState()
        formState.oauthAccountName = "old-name"
        var nextState = AccountPoolState(
            accounts: [AgentAccount(id: UUID(), name: "OAuth", usedUnits: 0, quota: 100)],
            mode: .manual
        )
        nextState.evaluate()
        var nextViewState = PoolDashboardViewState()
        nextViewState.oauthSuccessMessage = "ok"
        let output = PoolDashboardOAuthSignInFlowCoordinator.Output(
            state: nextState,
            viewState: nextViewState,
            oauthAccountName: "new-name",
            shouldRefreshLocalOAuthAccounts: false
        )
        let coordinator = PoolDashboardViewMutationCoordinator()

        coordinator.applyOAuthSignInOutput(
            output,
            state: &state,
            viewState: &viewState,
            formState: &formState
        )

        #expect(state.snapshot == nextState.snapshot)
        #expect(viewState.oauthSuccessMessage == "ok")
        #expect(formState.oauthAccountName == "new-name")
    }
}
