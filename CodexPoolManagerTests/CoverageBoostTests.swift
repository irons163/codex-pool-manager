import Foundation
import SwiftUI
import Testing
@testable import CodexPoolManager

private enum CoverageBoostMockError: Error {
    case expected
}

private final class MockOAuthLoginService: OAuthLoginServicing {
    let result: Result<OAuthTokens, Error>
    let capturedConfigurations = LockedValue<[OAuthClientConfiguration]>([])

    init(result: Result<OAuthTokens, Error>) {
        self.result = result
    }

    func signIn(configuration: OAuthClientConfiguration) async throws -> OAuthTokens {
        capturedConfigurations.withLock { $0.append(configuration) }
        return try result.get()
    }
}

private final class MockCodexUsageFetcher: CodexUsageFetching {
    let result: Result<CodexUsage, Error>
    let capturedRequests = LockedValue<[(token: String, accountID: String)]>([])

    init(result: Result<CodexUsage, Error>) {
        self.result = result
    }

    func fetchUsage(accessToken: String, accountID: String) async throws -> CodexUsage {
        capturedRequests.withLock { $0.append((accessToken, accountID)) }
        return try result.get()
    }
}

private func makeOAuthIDToken(payload: [String: Any]) throws -> String {
    let payloadData = try JSONSerialization.data(withJSONObject: payload)
    let encodedPayload = payloadData.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "header.\(encodedPayload).sig"
}

private func withTemporaryAuthFile(
    json: String,
    _ body: (URL) throws -> Void
) throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-auth-\(UUID().uuidString).json")
    try Data(json.utf8).write(to: url, options: .atomic)
    defer { try? FileManager.default.removeItem(at: url) }
    try body(url)
}

struct CodexAuthSwitchServiceCoverageTests {
    @Test
    func codexLaunchTargetMetadataCoversAllCases() {
        for target in CodexLaunchTarget.allCases {
            #expect(!target.title.isEmpty)
            _ = target.bundleIdentifiers
            _ = target.appURLs
        }

        #expect(CodexLaunchTarget.supportedTargets.contains(.codex))
        #expect(CodexLaunchTarget.supportedTargets.contains(.chatgpt))
        #expect(CodexLaunchTarget.advancedTargets.contains(.vscode))
        #expect(CodexLaunchTarget.pickerTargets.contains(.terminal))
        #expect(!CodexLaunchTarget.pickerTargets.contains(.auto))
    }

    @Test
    func codexLaunchTargetNormalizedRawValueFallsBackSafely() {
        #expect(CodexLaunchTarget.normalizedRawValue("codex") == CodexLaunchTarget.codex.rawValue)
        #expect(CodexLaunchTarget.normalizedRawValue("auto") == CodexLaunchTarget.defaultPickerTarget.rawValue)
        #expect(CodexLaunchTarget.normalizedRawValue("unknown") == CodexLaunchTarget.defaultPickerTarget.rawValue)
        #expect(CodexLaunchTarget.normalizedRawValue(" finder ") == CodexLaunchTarget.defaultPickerTarget.rawValue)
    }

    @Test
    func codexAuthSwitchErrorLocalizedDescriptionsAreAvailable() {
        let appStillRunning = CodexAuthSwitchError.appStillRunning(bundleIdentifier: "com.openai.codex")
        #expect(appStillRunning.localizedDescription.contains("com.openai.codex"))
        #expect(!CodexAuthSwitchError.appNotFound.localizedDescription.isEmpty)
        #expect(!CodexAuthSwitchError.unsupportedPlatform.localizedDescription.isEmpty)
        #expect(
            CodexAuthSwitchError.launchFailedAfterSwitch(reason: "boom")
                .localizedDescription.contains("boom")
        )
    }

    @Test
    @MainActor
    func codexAuthSwitchServicePerformSwitchOnlyRewritesAuthFile() throws {
        let service = CodexAuthSwitchService()
        let account = AgentAccount(
            id: UUID(),
            name: "new-user@example.com",
            usedUnits: 0,
            quota: 100,
            apiToken: "new-token"
        )
        let sourceJSON = """
        {
          "session": {
            "access_token": "old-token",
            "profile": { "email": "old@example.com" },
            "account_id": "old-account"
          }
        }
        """

        try withTemporaryAuthFile(json: sourceJSON) { authURL in
            try service.performSwitchOnly(
                authFileURL: authURL,
                account: account,
                chatGPTAccountID: "new-account"
            )

            let rewritten = try Data(contentsOf: authURL)
            let root = try #require(JSONSerialization.jsonObject(with: rewritten) as? [String: Any])
            let session = try #require(root["session"] as? [String: Any])
            let profile = try #require(session["profile"] as? [String: Any])

            #expect(session["access_token"] as? String == "new-token")
            #expect(session["account_id"] as? String == "new-account")
            #expect(profile["email"] as? String == "new-user@example.com")
        }
    }

    @Test
    @MainActor
    func codexAuthSwitchServicePerformSwitchOnlyThrowsOnInvalidJSON() throws {
        let service = CodexAuthSwitchService()
        let account = AgentAccount(
            id: UUID(),
            name: "demo@example.com",
            usedUnits: 0,
            quota: 100,
            apiToken: "token"
        )

        try withTemporaryAuthFile(json: "not-json") { authURL in
            #expect(throws: CodexAuthFileSwitcher.SwitchError.invalidJSON) {
                try service.performSwitchOnly(
                    authFileURL: authURL,
                    account: account,
                    chatGPTAccountID: "acct-1"
                )
            }
        }
    }
}

struct PoolDashboardAuthFlowCoordinatorCoverageTests {
    @Test
    func authFlowBuildConfigurationTrimsAndKeepsWorkspaceScope() throws {
        let coordinator = PoolDashboardAuthFlowCoordinator()

        let config = try coordinator.buildConfiguration(
            issuer: " https://auth.openai.com ",
            clientID: " app-client ",
            scopes: " openid profile email ",
            redirectURI: " http://localhost:1455/auth/callback ",
            originator: " codex_cli_rs ",
            workspaceID: " org-abc "
        )

        #expect(config.issuer.absoluteString == "https://auth.openai.com")
        #expect(config.clientID == "app-client")
        #expect(config.scopes == "openid profile email")
        #expect(config.redirectURI == "http://localhost:1455/auth/callback")
        #expect(config.originator == "codex_cli_rs")
        #expect(config.forcedWorkspaceID == "org-abc")
    }

    @Test
    func authFlowBuildConfigurationRejectsInvalidInputs() {
        let coordinator = PoolDashboardAuthFlowCoordinator()

        #expect(throws: PoolDashboardAuthFlowError.invalidConfiguration) {
            _ = try coordinator.buildConfiguration(
                issuer: "invalid-url",
                clientID: "",
                scopes: "openid",
                redirectURI: "http://localhost:1455/auth/callback",
                originator: "codex_cli_rs",
                workspaceID: ""
            )
        }
    }

    @Test
    func authFlowFetchOAuthSignInContextUsesLoginServiceAndUsageFetcher() async throws {
        let coordinator = PoolDashboardAuthFlowCoordinator()
        let idToken = try makeOAuthIDToken(payload: [
            "sub": "user-123",
            "account_id": "acct-123",
            "email": "demo@example.com"
        ])
        let loginService = MockOAuthLoginService(result: .success(
            OAuthTokens(
                accessToken: "access-1",
                refreshToken: "refresh-1",
                idToken: idToken
            )
        ))
        let usageFetcher = MockCodexUsageFetcher(result: .success(
            CodexUsage(
                usedUnits: 12,
                quota: 100,
                accountID: "acct-123",
                accountEmail: "demo@example.com",
                isPaid: true
            )
        ))
        let config = try coordinator.buildConfiguration(
            issuer: "https://auth.openai.com",
            clientID: "client",
            scopes: "openid profile email",
            redirectURI: "http://localhost:1455/auth/callback",
            originator: "codex_cli_rs",
            workspaceID: ""
        )

        let context = try await coordinator.fetchOAuthSignInContext(
            configuration: config,
            loginService: loginService,
            usageClient: usageFetcher
        )

        #expect(context.claims?.accountID == "acct-123")
        #expect(context.identityScope == AgentAccount.personalIdentityScope)
        #expect(context.usage?.usedUnits == 12)
        #expect(loginService.capturedConfigurations.value.count == 1)
        #expect(usageFetcher.capturedRequests.value.count == 1)
        #expect(usageFetcher.capturedRequests.value.first?.accountID == "acct-123")
    }

    @Test
    func authFlowMakeOAuthSignInContextFallsBackToSubjectWhenAccountIDMissing() async throws {
        let coordinator = PoolDashboardAuthFlowCoordinator()
        let idToken = try makeOAuthIDToken(payload: [
            "sub": "user-only-subject",
            "email": "subject@example.com"
        ])
        let usageFetcher = MockCodexUsageFetcher(result: .success(
            CodexUsage(usedUnits: 1, quota: 50, accountID: "user-only-subject")
        ))

        let context = await coordinator.makeOAuthSignInContext(
            tokens: OAuthTokens(accessToken: "token", refreshToken: nil, idToken: idToken),
            usageClient: usageFetcher
        )

        #expect(context.claims?.subject == "user-only-subject")
        #expect(usageFetcher.capturedRequests.value.first?.accountID == "user-only-subject")
    }

    @Test
    func authFlowMakeOAuthSignInContextSwallowsUsageFetchErrors() async throws {
        let coordinator = PoolDashboardAuthFlowCoordinator()
        let idToken = try makeOAuthIDToken(payload: [
            "sub": "user-err",
            "account_id": "acct-err"
        ])
        let usageFetcher = MockCodexUsageFetcher(result: .failure(CoverageBoostMockError.expected))

        let context = await coordinator.makeOAuthSignInContext(
            tokens: OAuthTokens(accessToken: "token", refreshToken: nil, idToken: idToken),
            usageClient: usageFetcher
        )

        #expect(context.claims?.accountID == "acct-err")
        #expect(context.usage == nil)
        #expect(usageFetcher.capturedRequests.value.count == 1)
    }

    @Test
    func authFlowFetchLocalImportContextRejectsMissingAccountDecision() async {
        let coordinator = PoolDashboardAuthFlowCoordinator()
        let usageFetcher = MockCodexUsageFetcher(result: .success(CodexUsage(usedUnits: 0, quota: 100)))

        await #expect(throws: PoolDashboardAuthFlowError.invalidImportDecision) {
            _ = try await coordinator.fetchLocalImportContext(
                decision: .missingAccountID,
                usageClient: usageFetcher
            )
        }
    }

    @Test
    func authFlowFetchLocalImportContextReturnsResolvedUsageContext() async throws {
        let coordinator = PoolDashboardAuthFlowCoordinator()
        let usageFetcher = MockCodexUsageFetcher(result: .success(CodexUsage(usedUnits: 44, quota: 1000)))

        let context = try await coordinator.fetchLocalImportContext(
            decision: .importAccount(
                name: "Imported",
                accessToken: "token-local",
                chatGPTAccountID: "acct-local"
            ),
            usageClient: usageFetcher
        )

        #expect(context.name == "Imported")
        #expect(context.accessToken == "token-local")
        #expect(context.chatGPTAccountID == "acct-local")
        #expect(context.usage.usedUnits == 44)
        #expect(usageFetcher.capturedRequests.value.first?.token == "token-local")
    }

    @Test
    func authFlowApplyLocalImportCreatesManagedAccount() {
        let coordinator = PoolDashboardAuthFlowCoordinator()
        var state = AccountPoolState(accounts: [], mode: .manual)
        let context = PoolDashboardAuthFlowCoordinator.LocalImportContext(
            name: "local@example.com",
            accessToken: "token-local",
            chatGPTAccountID: "acct-local",
            usage: CodexUsage(
                usedUnits: 22,
                quota: 200,
                usageWindowName: "weekly",
                accountID: "acct-local",
                accountEmail: "local@example.com"
            )
        )

        coordinator.applyLocalImport(state: &state, context: context)

        #expect(state.accounts.count == 1)
        #expect(state.accounts[0].chatGPTAccountID == "acct-local")
        #expect(state.accounts[0].usedUnits == 22)
        #expect(state.accounts[0].quota == 200)
    }

    @Test
    func authFlowLocalizedSyncErrorMapsKnownErrorKinds() {
        let coordinator = PoolDashboardAuthFlowCoordinator()

        #expect(coordinator.syncErrorKind(for: CodexSyncError.unauthorized) == .unauthorized)
        #expect(coordinator.syncErrorKind(for: CodexClientHTTPError(statusCode: 401)) == .unauthorized)
        #expect(coordinator.syncErrorKind(for: CodexClientHTTPError(statusCode: 429)) == .rateLimited)
        #expect(coordinator.syncErrorKind(for: URLError(.timedOut)) == .network)
        #expect(coordinator.syncErrorKind(for: CoverageBoostMockError.expected) == .unknown)
    }
}

struct PoolDashboardFlowCoordinatorCoverageTests {
    @Test
    func quickActionsFlowAppliesAllActions() {
        let coordinator = PoolDashboardQuickActionsFlowCoordinator()
        let accountID = UUID()
        var state = AccountPoolState(
            accounts: [AgentAccount(id: accountID, name: "A", usedUnits: 10, quota: 100)],
            mode: .manual
        )
        state.selectManualAccount(accountID)

        let simulated = coordinator.apply(.simulateUsage(15), to: state)
        #expect(simulated.accounts[0].usedUnits == 25)

        let evaluated = coordinator.apply(.evaluateSwitch, to: simulated)
        #expect(evaluated.mode == .manual)

        let cleared = coordinator.apply(.clearActivities, to: evaluated)
        #expect(cleared.activities.isEmpty)

        let removed = coordinator.apply(.removeAccount(accountID), to: cleared)
        #expect(removed.accounts.isEmpty)
    }

    @Test
    func quickActionsFlowResetAllUsageUsesLatchFlow() {
        let coordinator = PoolDashboardQuickActionsFlowCoordinator()
        let state = AccountPoolState(
            accounts: [
                AgentAccount(id: UUID(), name: "A", usedUnits: 30, quota: 100),
                AgentAccount(id: UUID(), name: "B", usedUnits: 40, quota: 100)
            ],
            mode: .manual
        )

        let first = coordinator.triggerResetAllUsage(from: state, resetAllLatch: DestructiveActionLatch())
        #expect(!first.didReset)

        let second = coordinator.triggerResetAllUsage(from: first.state, resetAllLatch: first.resetAllLatch)
        #expect(second.didReset)
        #expect(second.state.accounts.allSatisfy { $0.usedUnits == 0 })
    }

    @Test
    func backupFlowExportAndImportRoundTrip() {
        let coordinator = PoolDashboardBackupFlowCoordinator()
        var state = AccountPoolState(
            accounts: [AgentAccount(id: UUID(), name: "A", usedUnits: 12, quota: 120, apiToken: "token")],
            mode: .manual
        )
        var viewState = PoolDashboardViewState()

        coordinator.exportSnapshot(from: state, viewState: &viewState)
        #expect(!viewState.backupJSON.isEmpty)
        #expect(viewState.backupError == nil)

        let importSucceeded = coordinator.importSnapshot(state: &state, viewState: &viewState)
        #expect(importSucceeded)
        #expect(state.accounts.count == 1)
    }

    @Test
    func accountFormFlowAddAccountResetsFormInput() {
        let coordinator = PoolDashboardAccountFormFlowCoordinator()
        let state = AccountPoolState(accounts: [], mode: .manual)
        var formState = PoolDashboardFormState()
        formState.newAccountName = "Temp Name"
        formState.newAccountQuota = 777

        let output = coordinator.addAccount(
            from: state,
            formState: formState,
            name: formState.newAccountName,
            quota: formState.newAccountQuota
        )

        #expect(output.state.accounts.count == 1)
        #expect(output.state.accounts[0].name == "Temp Name")
        #expect(output.formState.newAccountName.isEmpty)
        #expect(output.formState.newAccountQuota == PoolDashboardFormState.defaultQuota)
    }
}

struct AppAppearancePreferenceCoverageTests {
    @Test
    func appAppearancePreferenceNormalizesLegacyValuesAndResolvesScheme() {
        #expect(AppAppearancePreference.normalizedRawValue("system") == AppAppearancePreference.system.rawValue)
        #expect(AppAppearancePreference.normalizedRawValue("Follow System") == AppAppearancePreference.system.rawValue)
        #expect(AppAppearancePreference.normalizedRawValue("Dark") == AppAppearancePreference.dark.rawValue)
        #expect(AppAppearancePreference.normalizedRawValue(" light ") == AppAppearancePreference.light.rawValue)
        #expect(AppAppearancePreference.normalizedRawValue("unknown") == AppAppearancePreference.system.rawValue)

        #expect(AppAppearancePreference.preferredColorScheme(for: "system") == nil)
        #expect(AppAppearancePreference.preferredColorScheme(for: "dark") == .dark)
        #expect(AppAppearancePreference.preferredColorScheme(for: "light") == .light)
        #expect(AppAppearancePreference.preferredColorScheme(for: "invalid") == nil)
    }
}
