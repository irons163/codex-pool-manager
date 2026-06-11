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
            apiKeyLogin: { _ in "" }
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
    func relaySwitchRequestSnapshotsAccountFields() throws {
        let accountID = UUID()
        let account = AgentAccount(
            id: accountID,
            name: "Mirror",
            usedUnits: 0,
            quota: 100,
            apiToken: " sk-relay ",
            credentialType: .relayAPIKey,
            relayProviderID: " mirror ",
            relayProviderName: " Mirror Provider ",
            relayBaseURL: " https://ai.liaryai.com/api/codex ",
            relayWireAPI: " responses ",
            relayRequiresOpenAIAuth: true
        )

        let request = try PoolDashboardRelayAccountCoordinator.SwitchRequest(account: account)

        #expect(request.accountID == accountID)
        #expect(request.accountName == "Mirror")
        #expect(request.apiKey == "sk-relay")
        #expect(String(decoding: request.apiKeyData, as: UTF8.self) == "sk-relay")
        #expect(request.provider.providerID == "mirror")
        #expect(request.provider.name == "Mirror Provider")
        #expect(request.provider.baseURL.absoluteString == "https://ai.liaryai.com/api/codex")
        #expect(request.provider.wireAPI == "responses")
        #expect(request.provider.requiresOpenAIAuth)
    }

    @Test
    func relaySwitchRequestUsesFallbackAPIKeyWhenAccountSnapshotIsRedacted() throws {
        let account = AgentAccount(
            id: UUID(),
            name: "Mirror",
            usedUnits: 0,
            quota: 100,
            apiToken: "",
            credentialType: .relayAPIKey,
            relayProviderID: "mirror",
            relayProviderName: "mirror",
            relayBaseURL: "https://ai.liaryai.com/api/codex",
            relayWireAPI: "responses",
            relayRequiresOpenAIAuth: true
        )

        let request = try PoolDashboardRelayAccountCoordinator.SwitchRequest(
            account: account,
            fallbackAPIKey: " sk-relay "
        )

        #expect(request.apiKey == "sk-relay")
        #expect(String(decoding: request.apiKeyData, as: UTF8.self) == "sk-relay")
    }

    @Test
    func relaySwitchRequestUsesFallbackAPIKeyWhenAccountSnapshotTokenIsWhitespace() throws {
        let account = AgentAccount(
            id: UUID(),
            name: "Mirror",
            usedUnits: 0,
            quota: 100,
            apiToken: " \n\t ",
            credentialType: .relayAPIKey,
            relayProviderID: "mirror",
            relayProviderName: "mirror",
            relayBaseURL: "https://ai.liaryai.com/api/codex",
            relayWireAPI: "responses",
            relayRequiresOpenAIAuth: true
        )
        let fallbackAPIKey = "relay-key-\(UUID().uuidString)"

        let request = try PoolDashboardRelayAccountCoordinator.SwitchRequest(
            account: account,
            fallbackAPIKey: " \(fallbackAPIKey)\n"
        )
        let requestMatchesFallback = request.apiKey == fallbackAPIKey
        let dataMatchesFallback = String(decoding: request.apiKeyData, as: UTF8.self) == fallbackAPIKey

        #expect(requestMatchesFallback)
        #expect(dataMatchesFallback)
    }

    @Test
    func relaySwitchDiagnosticRedactsAPIKeyValues() throws {
        let accountID = UUID()
        let account = AgentAccount(
            id: accountID,
            name: "Mirror",
            usedUnits: 0,
            quota: 100,
            apiToken: "sk-secret-token",
            credentialType: .relayAPIKey,
            relayProviderID: "mirror",
            relayProviderName: "mirror",
            relayBaseURL: "https://ai.liaryai.com/api/codex",
            relayWireAPI: "responses",
            relayRequiresOpenAIAuth: true
        )
        let request = try PoolDashboardRelayAccountCoordinator.SwitchRequest(account: account)

        let diagnostic = RelaySwitchDiagnostic(
            stage: "prepared",
            accountID: accountID,
            account: account,
            stateAccountCount: 3,
            relayAccountCount: 1,
            snapshotAPIKeyLength: account.apiToken.count,
            vaultAPIKeyLength: "sk-vault-token".count,
            hydratedFromVault: false,
            requestAPIKeyLength: request.apiKey.count,
            requestAPIKeyDataLength: request.apiKeyData.count,
            preserveOfficialAuth: true,
            switchWithoutLaunching: false,
            launchTarget: .codex,
            selectedAuthMethod: "relayAPIKey",
            storeType: "UserDefaultsAccountPoolStore",
            appVersion: "1.0.14",
            appBuild: "124"
        )
        let rendered = diagnostic.renderedLog()

        #expect(rendered.contains("Relay switch diagnostic"))
        #expect(rendered.contains("stage=prepared"))
        #expect(rendered.contains("account_id=\(accountID.uuidString)"))
        #expect(rendered.contains("credential_type=relay_api_key"))
        #expect(rendered.contains("snapshot_api_key_len=15"))
        #expect(rendered.contains("vault_api_key_len=14"))
        #expect(rendered.contains("request_api_key_data_len=15"))
        #expect(rendered.contains("app_version=1.0.14"))
        #expect(rendered.contains("app_build=124"))
        #expect(!rendered.contains("sk-secret-token"))
        #expect(!rendered.contains("sk-vault-token"))
    }

    @Test
    func relayCoordinatorSwitchesByApplyingConfigThenLoggingIn() async throws {
        let events = LockedValue<[String]>([])
        let coordinator = PoolDashboardRelayAccountCoordinator(
            configApplier: { provider in events.withLock { $0.append("config:\(provider.providerID)") } },
            apiKeyLogin: { apiKeyData in
                let apiKey = String(decoding: apiKeyData, as: UTF8.self)
                events.withLock { $0.append("login:api_key_len=\(apiKey.count)") }
                return "test_login_diagnostic=ok"
            },
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
            try PoolDashboardRelayAccountCoordinator.SwitchRequest(account: account),
            switchWithoutLaunching: false,
            launchTarget: .codex,
            viewState: PoolDashboardViewState()
        )

        #expect(events.value == ["config:mirror", "login:api_key_len=8", "launch:codex"])
        #expect(output.didSwitchAuth)
        #expect(output.viewState.switchLaunchError == nil)
        #expect(output.viewState.lastSwitchLaunchLog.contains("mirror"))
        #expect(output.viewState.lastSwitchLaunchLog.contains("test_login_diagnostic=ok"))
    }

    @Test
    func relayCoordinatorDefaultLoginWritesRequestAPIKeyAndSanitizedDiagnostics() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-coordinator-default-login-\(UUID().uuidString)", isDirectory: true)
        let authURL = directory.appendingPathComponent("auth.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let apiKey = "relay-key-\(UUID().uuidString)"
        let coordinator = PoolDashboardRelayAccountCoordinator(
            configApplier: { _ in },
            apiKeyLoginService: CodexAPIKeyLoginService(authFileURLProvider: { authURL }),
            appRelauncher: { _ in true }
        )
        let account = AgentAccount(
            id: UUID(),
            name: "Mirror",
            usedUnits: 0,
            quota: 100,
            apiToken: apiKey,
            credentialType: .relayAPIKey,
            relayProviderID: "mirror",
            relayProviderName: "mirror",
            relayBaseURL: "https://ai.liaryai.com/api/codex",
            relayWireAPI: "responses",
            relayRequiresOpenAIAuth: true
        )
        let request = try PoolDashboardRelayAccountCoordinator.SwitchRequest(account: account)
        let diagnostic = RelaySwitchDiagnostic(
            stage: "prepared",
            accountID: account.id,
            account: account,
            requestAPIKeyLength: request.apiKey.count,
            requestAPIKeyDataLength: request.apiKeyData.count
        ).renderedLog()

        let output = await coordinator.switchToRelayAccount(
            request,
            switchWithoutLaunching: true,
            diagnosticLog: diagnostic,
            viewState: PoolDashboardViewState()
        )

        let data = try Data(contentsOf: authURL)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let wroteExpectedAPIKey = object["OPENAI_API_KEY"] as? String == apiKey
        let log = output.viewState.lastSwitchLaunchLog
        #expect(output.didSwitchAuth)
        #expect(object["auth_mode"] as? String == "apikey")
        #expect(wroteExpectedAPIKey)
        #expect(log.contains("Relay switch diagnostic:"))
        #expect(log.contains("request_api_key_len=\(apiKey.count)"))
        #expect(log.contains("request_api_key_data_len=\(apiKey.count)"))
        #expect(log.contains("Relay API key auth diagnostic:"))
        #expect(log.contains("auth_write_stage=written"))
        #expect(log.contains("api_key_data_len=\(apiKey.count)"))
        #expect(log.contains("trimmed_api_key_len=\(apiKey.count)"))
        #expect(!log.contains(apiKey))
    }

    @Test
    func relayCoordinatorDefaultLoginPreservesAPIKeyAcrossOfficialAuthModes() async throws {
        for preserveOfficialAuth in [false, true] {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("relay-coordinator-preserve-\(preserveOfficialAuth)-\(UUID().uuidString)", isDirectory: true)
            let authURL = directory.appendingPathComponent("auth.json")
            defer { try? FileManager.default.removeItem(at: directory) }

            let apiKey = "relay-key-\(UUID().uuidString)"
            let events = LockedValue<[String]>([])
            let coordinator = PoolDashboardRelayAccountCoordinator(
                configApplier: { provider in
                    events.withLock { $0.append("config:\(provider.providerID)") }
                },
                enhancedConfigApplier: { provider, apiKey in
                    events.withLock { $0.append("enhanced:\(provider.providerID):api_key_len=\(apiKey.count)") }
                },
                apiKeyLoginService: CodexAPIKeyLoginService(authFileURLProvider: { authURL }),
                appRelauncher: { _ in true }
            )
            let account = AgentAccount(
                id: UUID(),
                name: "Mirror",
                usedUnits: 0,
                quota: 100,
                apiToken: apiKey,
                credentialType: .relayAPIKey,
                relayProviderID: "mirror",
                relayProviderName: "mirror",
                relayBaseURL: "https://ai.liaryai.com/api/codex",
                relayWireAPI: "responses",
                relayRequiresOpenAIAuth: true
            )

            let output = await coordinator.switchToRelayAccount(
                try PoolDashboardRelayAccountCoordinator.SwitchRequest(account: account),
                switchWithoutLaunching: true,
                preserveOfficialAuth: preserveOfficialAuth,
                viewState: PoolDashboardViewState()
            )

            let data = try Data(contentsOf: authURL)
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let wroteExpectedAPIKey = object["OPENAI_API_KEY"] as? String == apiKey
            #expect(output.didSwitchAuth)
            #expect(wroteExpectedAPIKey)
            #expect(object["auth_mode"] as? String == "apikey")
            #expect(!output.viewState.lastSwitchLaunchLog.contains(apiKey))
            if preserveOfficialAuth {
                #expect(events.value == ["enhanced:mirror:api_key_len=\(apiKey.count)"])
            } else {
                #expect(events.value == ["config:mirror"])
            }
        }
    }

    @Test
    func relaySwitchRequestUsesVaultFallbackFromRedactedStoredSnapshot() throws {
        let suiteName = "RelaySwitchRequestFallback.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Cannot create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let accountID = UUID()
        let apiKey = "relay-key-\(UUID().uuidString)"
        let vault = InMemoryAccountTokenVault()
        let store = UserDefaultsAccountPoolStore(defaults: defaults, key: "snapshot", tokenVault: vault)
        let snapshot = AccountPoolSnapshot(
            accounts: [
                AgentAccount(
                    id: accountID,
                    name: "Mirror",
                    usedUnits: 0,
                    quota: 100,
                    apiToken: apiKey,
                    credentialType: .relayAPIKey,
                    relayProviderID: "mirror",
                    relayProviderName: "mirror",
                    relayBaseURL: "https://ai.liaryai.com/api/codex",
                    relayWireAPI: "responses",
                    relayRequiresOpenAIAuth: true
                )
            ],
            groups: [],
            activities: [],
            mode: .manual,
            activeAccountID: accountID,
            manualAccountID: accountID,
            focusLockedAccountID: nil,
            minSwitchInterval: 300,
            lowUsageThresholdRatio: 0.15,
            minUsageRatioDeltaToSwitch: 0,
            lastSwitchAt: nil
        )

        store.save(snapshot)
        let rawData = try #require(defaults.data(forKey: "snapshot"))
        let rawJSON = String(data: rawData, encoding: .utf8) ?? ""
        let redactedSnapshot = try JSONDecoder().decode(AccountPoolSnapshot.self, from: rawData)
        let redactedAccount = try #require(redactedSnapshot.accounts.first)
        let fallbackAPIKey = store.apiToken(for: accountID)

        let request = try PoolDashboardRelayAccountCoordinator.SwitchRequest(
            account: redactedAccount,
            fallbackAPIKey: fallbackAPIKey
        )
        let requestMatchesVaultKey = request.apiKey == apiKey
        let requestDataMatchesVaultKey = String(decoding: request.apiKeyData, as: UTF8.self) == apiKey

        #expect(redactedAccount.apiToken.isEmpty)
        #expect(!rawJSON.contains(apiKey))
        #expect(fallbackAPIKey?.count == apiKey.count)
        #expect(requestMatchesVaultKey)
        #expect(requestDataMatchesVaultKey)
    }

    @Test
    func relayAccountCanSwitchImmediatelyAfterAddAndRedactedStoreRoundTrip() async throws {
        let suiteName = "RelayImmediateSwitch.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Cannot create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-immediate-switch-\(UUID().uuidString)", isDirectory: true)
        let authURL = directory.appendingPathComponent("auth.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let apiKey = "relay-key-\(UUID().uuidString)"
        let vault = InMemoryAccountTokenVault()
        let store = UserDefaultsAccountPoolStore(defaults: defaults, key: "snapshot", tokenVault: vault)
        let coordinator = PoolDashboardRelayAccountCoordinator(
            configApplier: { _ in },
            apiKeyLoginService: CodexAPIKeyLoginService(authFileURLProvider: { authURL }),
            appRelauncher: { _ in true }
        )

        let addOutput = await coordinator.addRelayAccount(
            to: AccountPoolState(accounts: [], mode: .manual),
            viewState: PoolDashboardViewState(),
            name: "Mirror",
            providerID: "mirror",
            providerName: "mirror",
            baseURL: "https://ai.liaryai.com/api/codex",
            wireAPI: "responses",
            apiKey: apiKey
        )
        store.save(addOutput.state.snapshot)
        let rawData = try #require(defaults.data(forKey: "snapshot"))
        let rawJSON = String(data: rawData, encoding: .utf8) ?? ""
        let redactedSnapshot = try JSONDecoder().decode(AccountPoolSnapshot.self, from: rawData)
        let redactedAccount = try #require(redactedSnapshot.accounts.first)
        let fallbackAPIKey = store.apiToken(for: redactedAccount.id)
        let request = try PoolDashboardRelayAccountCoordinator.SwitchRequest(
            account: redactedAccount,
            fallbackAPIKey: fallbackAPIKey
        )
        let output = await coordinator.switchToRelayAccount(
            request,
            switchWithoutLaunching: true,
            viewState: PoolDashboardViewState()
        )

        let authData = try Data(contentsOf: authURL)
        let authObject = try #require(JSONSerialization.jsonObject(with: authData) as? [String: Any])
        let wroteExpectedAPIKey = authObject["OPENAI_API_KEY"] as? String == apiKey
        let log = output.viewState.lastSwitchLaunchLog
        #expect(addOutput.viewState.relayError == nil)
        #expect(redactedAccount.apiToken.isEmpty)
        #expect(!rawJSON.contains(apiKey))
        #expect(fallbackAPIKey?.count == apiKey.count)
        #expect(output.didSwitchAuth)
        #expect(wroteExpectedAPIKey)
        #expect(log.contains("api_key_data_len=\(apiKey.count)"))
        #expect(!log.contains(apiKey))
    }

    @Test
    func relayCoordinatorKeepsDiagnosticPrefixInSwitchLog() async throws {
        let coordinator = PoolDashboardRelayAccountCoordinator(
            configApplier: { _ in },
            apiKeyLogin: { _ in "" },
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

        let output = await coordinator.switchToRelayAccount(
            try PoolDashboardRelayAccountCoordinator.SwitchRequest(account: account),
            switchWithoutLaunching: true,
            diagnosticLog: "Relay switch diagnostic:\nrequest_api_key_data_len=8",
            viewState: PoolDashboardViewState()
        )

        #expect(output.didSwitchAuth)
        #expect(output.viewState.lastSwitchLaunchLog.contains("Relay switch diagnostic"))
        #expect(output.viewState.lastSwitchLaunchLog.contains("request_api_key_data_len=8"))
        #expect(!output.viewState.lastSwitchLaunchLog.contains("sk-relay"))
    }

    @Test
    func relayCoordinatorEnhancedModeAppliesOpenAIHistoryConfigThenLogsInAPIKey() async throws {
        let events = LockedValue<[String]>([])
        let coordinator = PoolDashboardRelayAccountCoordinator(
            configApplier: { provider in events.withLock { $0.append("legacy:\(provider.providerID)") } },
            enhancedConfigApplier: { provider, apiKey in
                events.withLock { $0.append("enhanced:\(provider.providerID):api_key_len=\(apiKey.count)") }
            },
            apiKeyLogin: { apiKeyData in
                let apiKey = String(decoding: apiKeyData, as: UTF8.self)
                events.withLock { $0.append("login:api_key_len=\(apiKey.count)") }
                return ""
            },
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
            try PoolDashboardRelayAccountCoordinator.SwitchRequest(account: account),
            switchWithoutLaunching: false,
            preserveOfficialAuth: true,
            launchTarget: .codex,
            viewState: PoolDashboardViewState()
        )

        #expect(events.value == ["enhanced:mirror:api_key_len=8", "login:api_key_len=8", "launch:codex"])
        #expect(output.didSwitchAuth)
        #expect(output.viewState.switchLaunchError == nil)
        #expect(output.viewState.lastSwitchLaunchLog.contains(L10n.text("relay.switch.preserve_official_auth_enabled")))
    }

    @Test
    func relayCoordinatorSkipsRelaunchWhenSwitchWithoutLaunchingIsEnabled() async throws {
        let events = LockedValue<[String]>([])
        let coordinator = PoolDashboardRelayAccountCoordinator(
            configApplier: { provider in events.withLock { $0.append("config:\(provider.providerID)") } },
            apiKeyLogin: { apiKeyData in
                let apiKey = String(decoding: apiKeyData, as: UTF8.self)
                events.withLock { $0.append("login:api_key_len=\(apiKey.count)") }
                return ""
            },
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
            try PoolDashboardRelayAccountCoordinator.SwitchRequest(account: account),
            switchWithoutLaunching: true,
            launchTarget: .codex,
            viewState: PoolDashboardViewState()
        )

        #expect(events.value == ["config:mirror", "login:api_key_len=8"])
        #expect(output.didSwitchAuth)
        #expect(output.viewState.switchLaunchError == nil)
        #expect(output.viewState.lastSwitchLaunchLog.contains(L10n.text("switch.service.log.launch_skipped_by_setting")))
    }

    @Test
    func relayCoordinatorKeepsSwitchSuccessfulWhenRelaunchFails() async throws {
        let coordinator = PoolDashboardRelayAccountCoordinator(
            configApplier: { _ in },
            apiKeyLogin: { _ in "" },
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
            try PoolDashboardRelayAccountCoordinator.SwitchRequest(account: account),
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
    func relaySwitchDoesNotRequireAuthJSONFields() async throws {
        let coordinator = PoolDashboardRelayAccountCoordinator(
            configApplier: { _ in },
            apiKeyLogin: { _ in "" },
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

        let output = await coordinator.switchToRelayAccount(
            try PoolDashboardRelayAccountCoordinator.SwitchRequest(account: account),
            viewState: PoolDashboardViewState()
        )

        #expect(account.chatGPTAccountID == nil)
        #expect(output.viewState.switchLaunchError == nil)
        #expect(output.viewState.lastSwitchLaunchLog.contains(L10n.text("relay.switch.login_completed")))
    }

    @Test
    func relayCoordinatorIncludesAPIKeyLoginDiagnosticWhenLoginFails() async throws {
        let coordinator = PoolDashboardRelayAccountCoordinator(
            configApplier: { _ in },
            apiKeyLogin: { _ in
                throw CodexAPIKeyLoginError.loginFailed(
                    "login failed",
                    diagnosticLog: "Relay API key auth diagnostic:\nauth_write_stage=missing_api_key"
                )
            },
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

        let output = await coordinator.switchToRelayAccount(
            try PoolDashboardRelayAccountCoordinator.SwitchRequest(account: account),
            viewState: PoolDashboardViewState()
        )

        #expect(!output.didSwitchAuth)
        #expect(output.viewState.lastSwitchLaunchLog.contains("Relay API key auth diagnostic:"))
        #expect(output.viewState.lastSwitchLaunchLog.contains("auth_write_stage=missing_api_key"))
        #expect(!output.viewState.lastSwitchLaunchLog.contains("sk-relay"))
    }
}
