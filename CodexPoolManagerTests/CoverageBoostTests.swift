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

    @Test
    @MainActor
    func codexAuthSwitchServicePerformSwitchAndLaunchRewritesAuthFileBeforeLaunch() async throws {
        let service = CodexAuthSwitchService()
        let account = AgentAccount(
            id: UUID(),
            name: "display-name-only",
            usedUnits: 0,
            quota: 100,
            apiToken: "launch-token"
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

        let authURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-auth-launch-\(UUID().uuidString).json")
        try Data(sourceJSON.utf8).write(to: authURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: authURL) }

        var launchError: Error?
        do {
            try await service.performSwitchAndLaunch(
                authFileURL: authURL,
                account: account,
                chatGPTAccountID: "launch-account",
                launchTarget: .antigravity
            )
        } catch {
            launchError = error
        }

        let rewritten = try Data(contentsOf: authURL)
        let root = try #require(JSONSerialization.jsonObject(with: rewritten) as? [String: Any])
        let session = try #require(root["session"] as? [String: Any])
        let profile = try #require(session["profile"] as? [String: Any])

        #expect(session["access_token"] as? String == "launch-token")
        #expect(session["account_id"] as? String == "launch-account")
        #expect(profile["email"] as? String == "old@example.com")
        if let launchError {
            #expect(launchError is CodexAuthSwitchError)
        }
    }
}

struct CodexAuthSwitchServiceDebugHelperTests {
    @Test
    func launchSetHelpersReturnStableUniqueValues() {
        let service = CodexAuthSwitchService()

        let autoClose = service.debugCloseBundleIdentifiers(for: .auto)
        #expect(autoClose == ["com.openai.chatgpt", "com.openai.codex"])

        let autoLaunchIDs = service.debugLaunchBundleIdentifiers(for: .auto)
        #expect(autoLaunchIDs.contains("com.openai.chatgpt"))
        #expect(autoLaunchIDs.contains("com.openai.codex"))
        #expect(autoLaunchIDs.contains("com.apple.Terminal"))
        #expect(autoLaunchIDs.count == Set(autoLaunchIDs).count)

        let intellijBundleIDs = service.debugLaunchBundleIdentifiers(for: .intellijIDEA)
        #expect(intellijBundleIDs == ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"])

        let autoURLs = service.debugLaunchAppURLs(for: .auto).map(\.path)
        #expect(autoURLs.contains("/Applications/ChatGPT.app"))
        #expect(autoURLs.contains("/Applications/Codex.app"))
        #expect(autoURLs.contains("/System/Applications/Utilities/Terminal.app"))
        #expect(autoURLs.count == Set(autoURLs).count)

        let uniques = service.debugOrderedUniqueValues(of: [1, 2, 1, 3, 2, 4])
        #expect(uniques == [1, 2, 3, 4])
    }
}

struct MenuBarSnapshotFormatterTests {
    @Test
    func menuBarTitleFallsBackWhenNoSnapshot() {
        #expect(MenuBarSnapshotFormatter.menuBarTitle(snapshot: nil) == "Codex --")
    }

    @Test
    func menuBarTitleFormatsPaidSnapshotWithWeeklyAndFiveHourRemaining() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = MenuBarBridgeSnapshot(
            updatedAt: now.addingTimeInterval(-80),
            activeAccountName: "paid@example.com",
            activeIsPaid: true,
            activeRemainingUnits: 25,
            activeQuota: 50,
            activeFiveHourRemainingPercent: 42,
            activeWeeklyResetAt: nil,
            activeFiveHourResetAt: nil
        )

        let title = MenuBarSnapshotFormatter.menuBarTitle(snapshot: snapshot, now: now)
        #expect(title == "Codex w 50% · 5h 42% · 1m")
    }

    @Test
    func menuBarTitleFormatsNonPaidSnapshotUsingRemainingPercent() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let snapshot = MenuBarBridgeSnapshot(
            updatedAt: now.addingTimeInterval(-8),
            activeAccountName: "free@example.com",
            activeIsPaid: false,
            activeRemainingUnits: 33,
            activeQuota: 100,
            activeFiveHourRemainingPercent: nil,
            activeWeeklyResetAt: nil,
            activeFiveHourResetAt: nil
        )

        let title = MenuBarSnapshotFormatter.menuBarTitle(snapshot: snapshot, now: now)
        #expect(title == "Codex 33% · now")
    }

    @Test
    func menuBarTitleFormatsRawUnitsWhenQuotaUnavailable() {
        let now = Date(timeIntervalSince1970: 3_000_000)
        let snapshot = MenuBarBridgeSnapshot(
            updatedAt: now.addingTimeInterval(-3_800),
            activeAccountName: "unknown@example.com",
            activeIsPaid: false,
            activeRemainingUnits: 7,
            activeQuota: nil,
            activeFiveHourRemainingPercent: nil,
            activeWeeklyResetAt: nil,
            activeFiveHourResetAt: nil
        )

        let title = MenuBarSnapshotFormatter.menuBarTitle(snapshot: snapshot, now: now)
        #expect(title == "Codex 7 · 1h")
    }

    @Test
    func shortAgeTextHandlesRangeBoundaries() {
        let now = Date(timeIntervalSince1970: 4_000_000)
        #expect(MenuBarSnapshotFormatter.shortAgeText(since: now.addingTimeInterval(-9), now: now) == "now")
        #expect(MenuBarSnapshotFormatter.shortAgeText(since: now.addingTimeInterval(-15), now: now) == "15s")
        #expect(MenuBarSnapshotFormatter.shortAgeText(since: now.addingTimeInterval(-180), now: now) == "3m")
        #expect(MenuBarSnapshotFormatter.shortAgeText(since: now.addingTimeInterval(-7_200), now: now) == "2h")
        #expect(MenuBarSnapshotFormatter.shortAgeText(since: now.addingTimeInterval(-172_800), now: now) == "2d")
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

@MainActor
struct OAuthSupportCoverageBoostTests {
    @Test
    func oauthClientConfigurationCallbackSchemeParsesValidAndInvalidRedirects() {
        let valid = OAuthClientConfiguration(
            issuer: URL(string: "https://auth.example.com")!,
            scopes: "openid",
            redirectURI: "aiaagentpool://oauth/callback"
        )
        #expect(valid.callbackURLScheme == "aiaagentpool")

        let invalid = OAuthClientConfiguration(
            issuer: URL(string: "https://auth.example.com")!,
            scopes: "openid",
            redirectURI: "not a valid url"
        )
        #expect(invalid.callbackURLScheme == nil)
    }

    @Test
    func oauthIDTokenClaimsParserExtractsOrganizationUsingDefaultThenFirstFallback() throws {
        let defaultOrgToken = try makeOAuthIDToken(payload: [
            "sub": "user-default",
            "https://api.openai.com/auth": [
                "organizations": [
                    ["id": "org-other", "is_default": false],
                    ["id": "org-default", "is_default": true]
                ]
            ]
        ])
        let defaultClaims = try #require(OAuthIDTokenClaimsParser.parse(defaultOrgToken))
        #expect(defaultClaims.organizationID == "org-default")

        let fallbackFirstToken = try makeOAuthIDToken(payload: [
            "sub": "user-first",
            "https://api.openai.com/auth": [
                "organizations": [
                    ["id": "org-first"],
                    ["id": "org-second", "is_default": false]
                ]
            ]
        ])
        let fallbackClaims = try #require(OAuthIDTokenClaimsParser.parse(fallbackFirstToken))
        #expect(fallbackClaims.organizationID == "org-first")
    }

    @Test
    func oauthLoginErrorDescriptionsCoverAllCases() {
        let cases: [OAuthLoginError] = [
            .invalidAuthorizeURL,
            .invalidRedirectURI,
            .browserStartFailed,
            .invalidCallback,
            .localhostCallbackStartFailed("boom"),
            .localhostCallbackTimedOut,
            .authorizationFailed("denied"),
            .missingCode,
            .stateMismatch,
            .tokenExchangeFailed("unauthorized")
        ]

        for error in cases {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
    }

    @Test
    func oauthLoginServiceSignInRejectsInvalidRedirectBeforeLaunchingBrowser() async {
        let service = OAuthLoginService(session: .shared)
        let config = OAuthClientConfiguration(
            issuer: URL(string: "https://auth.example.com")!,
            scopes: "openid profile",
            redirectURI: "not a valid redirect"
        )

        await #expect(throws: OAuthLoginError.invalidRedirectURI) {
            _ = try await service.signIn(configuration: config)
        }
    }
}

struct PoolDashboardDebugCoverageHookTests {
    @Test
    func workspaceDrawerHooksCoverCycleAndMetadata() {
        let snapshots = PoolDashboardView.debugWorkspaceDrawerStateSnapshots()
        #expect(snapshots.count == 3)
        #expect(snapshots[0].isVisible == false)
        #expect(snapshots[0].symbolName == "chevron.right")
        #expect(snapshots[0].actionTitleKey == "drawer.expand")
        #expect(snapshots[0].nextSymbolName == "chevron.up")

        #expect(snapshots[1].isVisible)
        #expect(snapshots[1].symbolName == "chevron.up")
        #expect(snapshots[1].actionTitleKey == "drawer.expand_full")
        #expect(snapshots[1].nextSymbolName == "chevron.down")

        #expect(snapshots[2].isVisible)
        #expect(snapshots[2].symbolName == "chevron.down")
        #expect(snapshots[2].actionTitleKey == "drawer.collapse")
        #expect(snapshots[2].nextSymbolName == "chevron.right")
    }

    @Test
    func specialResetHooksExposeExpectedIdentifiersAndTitles() {
        let kinds = PoolDashboardView.debugSpecialResetKinds()
        #expect(kinds.count == 2)
        #expect(kinds[0].rawValue == "weekly")
        #expect(kinds[0].interval == 7 * 24 * 3_600)
        #expect(!kinds[0].title.isEmpty)
        #expect(kinds[1].rawValue == "fiveHour")
        #expect(kinds[1].interval == 5 * 3_600)
        #expect(!kinds[1].title.isEmpty)

        #expect(PoolDashboardView.debugSpecialResetRecordID(accountKey: "account:abc") == "account:abc")
        #expect(PoolDashboardView.debugAppUpdatePromptID(latestVersion: "1.2.3") == "1.2.3")
    }
}
