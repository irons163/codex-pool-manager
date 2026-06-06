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
        #expect(output.errorMessage?.contains(L10n.text("switch.error.prefix")) == true)
        #expect(output.switchLaunchLog.contains(L10n.text("switch.log.error_prefix")))
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
    func poolDashboardViewMutationCoordinatorApplyLifecycleSnapshotChangeOutputUpdatesPolicyAndViewState() {
        var lowUsageAlertPolicy = LowUsageAlertPolicy()
        var viewState = PoolDashboardViewState()
        viewState.syncError = "before"

        var nextPolicy = LowUsageAlertPolicy()
        _ = nextPolicy.shouldTriggerAlert(mode: .focus, hasLowUsageWarning: true)
        var nextViewState = PoolDashboardViewState()
        nextViewState.showLowUsageAlert = true
        nextViewState.syncError = "after"
        let output = PoolDashboardLifecycleFlowCoordinator.SnapshotChangeOutput(
            lowUsageAlertPolicy: nextPolicy,
            viewState: nextViewState
        )
        let coordinator = PoolDashboardViewMutationCoordinator()

        coordinator.applyLifecycleSnapshotChangeOutput(
            output,
            lowUsageAlertPolicy: &lowUsageAlertPolicy,
            viewState: &viewState
        )

        #expect(viewState.showLowUsageAlert)
        #expect(viewState.syncError == "after")
        let shouldTriggerAgain = lowUsageAlertPolicy.shouldTriggerAlert(mode: .focus, hasLowUsageWarning: true)
        #expect(!shouldTriggerAgain)
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
    func poolDashboardViewMutationCoordinatorApplyLocalImportOutputUpdatesStateViewModelAndViewState() {
        var state = AccountPoolState(
            accounts: [AgentAccount(id: UUID(), name: "Before", usedUnits: 1, quota: 10)],
            mode: .manual
        )
        var viewModel = LocalOAuthImportViewModel()
        viewModel.errorMessage = "before-error"
        var viewState = PoolDashboardViewState()
        viewState.syncError = "before-sync-error"

        let importedAccount = AgentAccount(id: UUID(), name: "Imported", usedUnits: 0, quota: 100)
        let nextState = AccountPoolState(accounts: [importedAccount], mode: .focus)
        let nextViewModel = LocalOAuthImportViewModel(accounts: [
            LocalCodexOAuthAccount(
                id: UUID().uuidString,
                displayName: "Imported OAuth",
                email: "imported@example.com",
                source: "~/.codex/auth.json",
                accessToken: "sk-imported",
                chatGPTAccountID: "account-imported"
            )
        ])
        var nextViewState = PoolDashboardViewState()
        nextViewState.oauthSuccessMessage = "import-ok"
        let output = PoolDashboardLocalImportFlowCoordinator.Output(
            state: nextState,
            viewModel: nextViewModel,
            viewState: nextViewState,
            didImport: true
        )
        let coordinator = PoolDashboardViewMutationCoordinator()

        coordinator.applyLocalImportOutput(
            output,
            state: &state,
            viewModel: &viewModel,
            viewState: &viewState
        )

        #expect(state.snapshot == nextState.snapshot)
        #expect(viewModel.accounts.count == 1)
        #expect(viewModel.accounts.first?.email == "imported@example.com")
        #expect(viewState.oauthSuccessMessage == "import-ok")
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

@MainActor
struct RelayAccountCoordinatorTests {
    @Test
    func relayCoordinatorAddsRelayAccountAndMarksUsageSyncUnavailable() async {
        let coordinator = PoolDashboardRelayAccountCoordinator(
            configApplier: { _ in },
            apiKeyLogin: { _ in }
        )
        var state = AccountPoolState(accounts: [], mode: .manual)
        var viewState = PoolDashboardViewState()

        let output = await coordinator.addRelayAccount(
            to: state,
            viewState: viewState,
            name: "Mirror",
            providerID: "mirror",
            providerName: "mirror",
            baseURL: "https://ai.liaryai.com/api/codex",
            wireAPI: "responses",
            apiKey: "sk-relay"
        )
        state = output.state
        viewState = output.viewState

        #expect(state.accounts.count == 1)
        #expect(state.accounts[0].credentialType == .relayAPIKey)
        #expect(state.accounts[0].apiToken == "sk-relay")
        #expect(state.accounts[0].relayProviderID == "mirror")
        #expect(state.accounts[0].isUsageSyncExcluded)
        #expect(state.accounts[0].usageSyncError == AgentAccount.relayUsageSyncUnavailableReason)
        #expect(viewState.relaySuccessMessage == L10n.text("relay.status.added"))
    }

    @Test
    func relayCoordinatorSwitchesByApplyingConfigThenLoggingIn() async {
        let events = LockedValue<[String]>([])
        let coordinator = PoolDashboardRelayAccountCoordinator(
            configApplier: { provider in events.withLock { $0.append("config:\(provider.providerID)") } },
            apiKeyLogin: { apiKey in events.withLock { $0.append("login:\(apiKey)") } },
            appRelauncher: { launchTarget in
                events.withLock { $0.append("launch:\(launchTarget.rawValue)") }
                return true
            }
        )
        let account = AgentAccount(
            id: UUID(),
            name: "Mirror",
            usedUnits: 0,
            quota: 100,
            apiToken: "sk-relay",
            credentialType: .relayAPIKey,
            relayProviderID: "mirror",
            relayProviderName: "mirror",
            relayBaseURL: "https://ai.liaryai.com/api/codex",
            relayWireAPI: "responses",
            relayRequiresOpenAIAuth: true
        )

        let output = await coordinator.switchToRelayAccount(
            account,
            switchWithoutLaunching: false,
            launchTarget: .codex,
            viewState: PoolDashboardViewState()
        )

        #expect(events.value == ["config:mirror", "login:sk-relay", "launch:codex"])
        #expect(output.didSwitchAuth)
        #expect(output.viewState.switchLaunchError == nil)
        #expect(output.viewState.lastSwitchLaunchLog.contains("mirror"))
    }

    @Test
    func relayCoordinatorEnhancedModeAppliesConfigAndSkipsAPIKeyLogin() async {
        let events = LockedValue<[String]>([])
        let coordinator = PoolDashboardRelayAccountCoordinator(
            configApplier: { provider in events.withLock { $0.append("legacy:\(provider.providerID)") } },
            enhancedConfigApplier: { provider, apiKey in
                events.withLock { $0.append("enhanced:\(provider.providerID):\(apiKey)") }
            },
            historyMigrator: { providerID in
                events.withLock { $0.append("history:\(providerID)") }
                return CodexRelayHistoryBucketMigrationOutcome(
                    migratedSessionFiles: 1,
                    migratedThreadRows: 2
                )
            },
            apiKeyLogin: { apiKey in events.withLock { $0.append("login:\(apiKey)") } },
            appRelauncher: { launchTarget in
                events.withLock { $0.append("launch:\(launchTarget.rawValue)") }
                return true
            }
        )
        let account = AgentAccount(
            id: UUID(),
            name: "Mirror",
            usedUnits: 0,
            quota: 100,
            apiToken: "sk-relay",
            credentialType: .relayAPIKey,
            relayProviderID: "mirror",
            relayProviderName: "mirror",
            relayBaseURL: "https://ai.liaryai.com/api/codex",
            relayWireAPI: "responses",
            relayRequiresOpenAIAuth: true
        )

        let output = await coordinator.switchToRelayAccount(
            account,
            switchWithoutLaunching: false,
            preserveOfficialAuth: true,
            launchTarget: .codex,
            viewState: PoolDashboardViewState()
        )

        #expect(events.value == ["enhanced:mirror:sk-relay", "history:mirror", "launch:codex"])
        #expect(output.didSwitchAuth)
        #expect(output.viewState.switchLaunchError == nil)
        #expect(output.viewState.lastSwitchLaunchLog.contains(L10n.text("relay.switch.preserve_official_auth_enabled")))
        #expect(output.viewState.lastSwitchLaunchLog.contains("mirror -> custom"))
    }

    @Test
    func relayCoordinatorSkipsRelaunchWhenSwitchWithoutLaunchingIsEnabled() async {
        let events = LockedValue<[String]>([])
        let coordinator = PoolDashboardRelayAccountCoordinator(
            configApplier: { provider in events.withLock { $0.append("config:\(provider.providerID)") } },
            apiKeyLogin: { apiKey in events.withLock { $0.append("login:\(apiKey)") } },
            appRelauncher: { _ in
                events.withLock { $0.append("launch") }
                return true
            }
        )
        let account = AgentAccount(
            id: UUID(),
            name: "Mirror",
            usedUnits: 0,
            quota: 100,
            apiToken: "sk-relay",
            credentialType: .relayAPIKey,
            relayProviderID: "mirror",
            relayProviderName: "mirror",
            relayBaseURL: "https://ai.liaryai.com/api/codex",
            relayWireAPI: "responses",
            relayRequiresOpenAIAuth: true
        )

        let output = await coordinator.switchToRelayAccount(
            account,
            switchWithoutLaunching: true,
            launchTarget: .codex,
            viewState: PoolDashboardViewState()
        )

        #expect(events.value == ["config:mirror", "login:sk-relay"])
        #expect(output.didSwitchAuth)
        #expect(output.viewState.switchLaunchError == nil)
        #expect(output.viewState.lastSwitchLaunchLog.contains(L10n.text("switch.service.log.launch_skipped_by_setting")))
    }

    @Test
    func relayCoordinatorKeepsSwitchSuccessfulWhenRelaunchFails() async {
        let coordinator = PoolDashboardRelayAccountCoordinator(
            configApplier: { _ in },
            apiKeyLogin: { _ in },
            appRelauncher: { _ in
                throw CodexAuthSwitchError.launchFailedAfterSwitch(reason: "Codex still running")
            }
        )
        let account = AgentAccount(
            id: UUID(),
            name: "Mirror",
            usedUnits: 0,
            quota: 100,
            apiToken: "sk-relay",
            credentialType: .relayAPIKey,
            relayProviderID: "mirror",
            relayProviderName: "mirror",
            relayBaseURL: "https://ai.liaryai.com/api/codex",
            relayWireAPI: "responses",
            relayRequiresOpenAIAuth: true
        )

        let output = await coordinator.switchToRelayAccount(
            account,
            switchWithoutLaunching: false,
            launchTarget: .codex,
            viewState: PoolDashboardViewState()
        )

        #expect(output.didSwitchAuth)
        #expect(output.viewState.switchLaunchError == nil)
        #expect(output.viewState.switchLaunchWarning == L10n.text("switch.warning.launch_failed_but_switched"))
        #expect(output.viewState.lastSwitchLaunchLog.contains("Codex still running"))
    }

    @Test
    func relaySwitchDoesNotRequireAuthJSONFields() async {
        let coordinator = PoolDashboardRelayAccountCoordinator(
            configApplier: { _ in },
            apiKeyLogin: { _ in },
            appRelauncher: { _ in true }
        )
        let account = AgentAccount(
            id: UUID(),
            name: "Mirror",
            usedUnits: 0,
            quota: 100,
            apiToken: "sk-relay",
            credentialType: .relayAPIKey,
            relayProviderID: "mirror",
            relayProviderName: "mirror",
            relayBaseURL: "https://ai.liaryai.com/api/codex",
            relayWireAPI: "responses",
            relayRequiresOpenAIAuth: true
        )

        let output = await coordinator.switchToRelayAccount(account, viewState: PoolDashboardViewState())

        #expect(account.chatGPTAccountID == nil)
        #expect(output.viewState.switchLaunchError == nil)
        #expect(output.viewState.lastSwitchLaunchLog.contains(L10n.text("relay.switch.login_completed")))
    }
}
