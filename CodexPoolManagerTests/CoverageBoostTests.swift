import Foundation
import SwiftUI
import Testing
@testable import CodexPoolManager
#if canImport(AppKit)
import AppKit
#endif

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
            #expect(target.id == target.rawValue)
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
        let service = CodexAuthSwitchService(providerConfigResetter: { _ in })
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
    func codexAuthSwitchServicePerformSwitchOnlyResetsProviderConfig() throws {
        let didResetProviderConfig = LockedValue(false)
        let resetAuthFileURL = LockedValue<URL?>(nil)
        let service = CodexAuthSwitchService(
            providerConfigResetter: { authFileURL in
                didResetProviderConfig.withLock { $0 = true }
                resetAuthFileURL.withLock { $0 = authFileURL }
            }
        )
        let account = AgentAccount(
            id: UUID(),
            name: "new-user@example.com",
            usedUnits: 0,
            quota: 100,
            apiToken: "new-token"
        )
        let sourceJSON = """
        {
          "auth_mode": "apikey",
          "OPENAI_API_KEY": "sk-old-api-key"
        }
        """

        try withTemporaryAuthFile(json: sourceJSON) { authURL in
            try service.performSwitchOnly(
                authFileURL: authURL,
                account: account,
                chatGPTAccountID: "new-account"
            )

            #expect(didResetProviderConfig.value)
            #expect(resetAuthFileURL.value == authURL)
        }
    }

    @Test
    @MainActor
    func codexAuthSwitchServiceRestoresOAuthMetadataFromSiblingAuthAccounts() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-auth-metadata-switch-\(UUID().uuidString)", isDirectory: true)
        let authURL = directory.appendingPathComponent("auth.json")
        let accountsDirectory = directory.appendingPathComponent("auth_accounts", isDirectory: true)
        let storedAccountURL = accountsDirectory.appendingPathComponent("account.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: accountsDirectory, withIntermediateDirectories: true)
        try """
        {
          "auth_mode": "apikey",
          "email": "oauth@example.com",
          "OPENAI_API_KEY": "sk-old-api-key"
        }
        """.write(to: authURL, atomically: true, encoding: .utf8)
        try """
        {
          "auth_mode": "chatgpt",
          "email": "oauth@example.com",
          "last_refresh": "2026-05-10T02:33:21.730788Z",
          "OPENAI_API_KEY": null,
          "tokens": {
            "access_token": "old-oauth-access-token",
            "account_id": "user-oauth-account",
            "refresh_token": "stored-refresh-token",
            "id_token": "stored-id-token"
          }
        }
        """.write(to: storedAccountURL, atomically: true, encoding: .utf8)

        let service = CodexAuthSwitchService(providerConfigResetter: { _ in })
        let account = AgentAccount(
            id: UUID(),
            name: "oauth@example.com",
            usedUnits: 0,
            quota: 100,
            apiToken: "new-oauth-access-token"
        )

        try service.performSwitchOnly(
            authFileURL: authURL,
            account: account,
            chatGPTAccountID: "user-oauth-account"
        )

        let rewritten = try Data(contentsOf: authURL)
        let root = try #require(JSONSerialization.jsonObject(with: rewritten) as? [String: Any])
        let tokens = try #require(root["tokens"] as? [String: Any])
        let apiKeyValue = try #require(root["OPENAI_API_KEY"])

        #expect(root["auth_mode"] as? String == "chatgpt")
        #expect(root["email"] as? String == "oauth@example.com")
        #expect(root["last_refresh"] as? String == "2026-05-10T02:33:21.730788Z")
        #expect(apiKeyValue is NSNull)
        #expect(tokens["access_token"] as? String == "new-oauth-access-token")
        #expect(tokens["account_id"] as? String == "user-oauth-account")
        #expect(tokens["refresh_token"] as? String == "stored-refresh-token")
        #expect(tokens["id_token"] as? String == "stored-id-token")
    }

    @Test
    @MainActor
    func codexAuthSwitchServiceDefaultResetterUsesAuthFileDirectoryConfig() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-auth-config-switch-\(UUID().uuidString)", isDirectory: true)
        let authURL = directory.appendingPathComponent("auth.json")
        let configURL = directory.appendingPathComponent("config.toml")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        {
          "auth_mode": "apikey",
          "OPENAI_API_KEY": "sk-old-api-key"
        }
        """.write(to: authURL, atomically: true, encoding: .utf8)
        try """
        model = "gpt-5.1-codex"
        model_provider = "mirror"

        [model_providers.mirror]
        name = "mirror"
        base_url = "https://ai.liaryai.com/api/codex"
        wire_api = "responses"
        requires_openai_auth = true
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let service = CodexAuthSwitchService()
        let account = AgentAccount(
            id: UUID(),
            name: "new-user@example.com",
            usedUnits: 0,
            quota: 100,
            apiToken: "new-token"
        )

        try service.performSwitchOnly(
            authFileURL: authURL,
            account: account,
            chatGPTAccountID: "new-account"
        )

        let resetConfig = try String(contentsOf: configURL, encoding: .utf8)
        #expect(!resetConfig.contains("\nmodel_provider = \"mirror\""))
        #expect(resetConfig.contains("[model_providers.mirror]"))
    }

    @Test
    @MainActor
    func codexAuthSwitchServicePerformSwitchOnlyThrowsOnInvalidJSON() throws {
        let service = CodexAuthSwitchService(providerConfigResetter: { _ in })
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
        let service = CodexAuthSwitchService(providerConfigResetter: { _ in })
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

    @Test
    func sandboxFlagHelperReflectsEnvironmentVariable() {
        let key = "APP_SANDBOX_CONTAINER_ID"
        let service = CodexAuthSwitchService()
        let original = ProcessInfo.processInfo.environment[key]

        if let original {
            setenv(key, original, 1)
        } else {
            unsetenv(key)
        }

        setenv(key, "sandbox-test", 1)
        #expect(service.debugIsSandboxedEnvironment())

        if let original {
            setenv(key, original, 1)
        } else {
            unsetenv(key)
        }
    }

    @Test
    func closeAndWaitHelpersHandleNonRunningBundleQuickly() async {
        let service = CodexAuthSwitchService()
        let bundleID = "com.irons.nonexistent.\(UUID().uuidString)"
        let closeResult = await service.debugCloseAppIfRunning(bundleIdentifier: bundleID)
        #expect(closeResult)

        let waitResult = await service.debugWaitUntilAppExits(
            bundleIdentifier: bundleID,
            timeoutNanoseconds: 1
        )
        #expect(waitResult)
    }

    @Test
    func launchAppHelperReturnsFalseForUnknownBundleIdentifier() async throws {
        let service = CodexAuthSwitchService()
        let unknownBundleID = "com.irons.missing.\(UUID().uuidString)"
        let didLaunch = try await service.debugLaunchApp(bundleIdentifier: unknownBundleID)
        #expect(!didLaunch)
    }

    @Test
    func launchRetryHelperReturnsFalseWhenNoCandidatesProvided() async throws {
        let service = CodexAuthSwitchService()
        let didLaunch = try await service.debugLaunchCodexAppWithRetry(
            launchBundleIDs: [],
            launchAppPaths: [],
            maxAttempts: 1
        )
        #expect(!didLaunch)
    }

    #if canImport(AppKit)
    @Test
    func closeHelperReturnsFalseForRunningAppInSandboxMode() async {
        let key = "APP_SANDBOX_CONTAINER_ID"
        let original = ProcessInfo.processInfo.environment[key]
        setenv(key, "sandbox-test", 1)
        defer {
            if let original {
                setenv(key, original, 1)
            } else {
                unsetenv(key)
            }
        }

        let runningBundleID = Bundle.main.bundleIdentifier ?? "com.apple.finder"
        let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: runningBundleID).isEmpty
        guard isRunning else { return }

        let service = CodexAuthSwitchService()
        let result = await service.debugCloseAppIfRunning(bundleIdentifier: runningBundleID)
        #expect(!result)
    }
    #endif
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

struct CodexPoolManagerAppMigrationCoverageTests {
    private let migrationMarkerKey = "did_migrate_sandbox_preferences_v1"
    private let snapshotKey = "account_pool_snapshot"
    private let tokenKey = "account_pool_tokens"

    private func makeDefaults() -> UserDefaults {
        let suiteName = "tests.coverage.app.migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test
    func migrationMarksCompletedWhenLegacyPreferencesUnavailable() {
        let defaults = makeDefaults()
        CodexPoolManagerApp.debugRunLegacyMigration(defaults: defaults, legacyPreferences: [:])
        #expect(defaults.bool(forKey: migrationMarkerKey))
    }

    @Test
    func migrationMergesTokensAndSnapshotWithoutOverwritingNonEmptyToken() {
        let defaults = makeDefaults()
        defaults.set(["keep": "existing-token", "fill": ""], forKey: tokenKey)

        let legacySnapshot = Data([1, 2, 3, 4])
        let legacy: [String: Any] = [
            tokenKey: [
                "keep": "legacy-should-not-replace",
                "fill": "legacy-fill",
                "new": "legacy-new"
            ],
            snapshotKey: legacySnapshot
        ]

        CodexPoolManagerApp.debugRunLegacyMigration(defaults: defaults, legacyPreferences: legacy)

        let mergedTokens = defaults.dictionary(forKey: tokenKey) as? [String: String]
        #expect(mergedTokens?["keep"] == "existing-token")
        #expect(mergedTokens?["fill"] == "legacy-fill")
        #expect(mergedTokens?["new"] == "legacy-new")
        #expect(defaults.data(forKey: snapshotKey) == legacySnapshot)
        #expect(defaults.bool(forKey: migrationMarkerKey))
    }

    @Test
    func migrationSkipsWhenMarkerAlreadySet() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: migrationMarkerKey)
        defaults.set(["a": "before"], forKey: tokenKey)

        let legacy: [String: Any] = [tokenKey: ["a": "after"]]
        CodexPoolManagerApp.debugRunLegacyMigration(defaults: defaults, legacyPreferences: legacy)

        let tokens = defaults.dictionary(forKey: tokenKey) as? [String: String]
        #expect(tokens?["a"] == "before")
    }

    @Test
    func preferenceNormalizerRewritesInvalidAppearanceAndLanguageValues() {
        let defaults = makeDefaults()
        defaults.set("bad-value", forKey: AppAppearancePreference.storageKey)
        defaults.set(" zh-cn ", forKey: L10n.languageOverrideKey)

        CodexPoolManagerApp.debugNormalizePreferences(defaults: defaults)

        #expect(defaults.string(forKey: AppAppearancePreference.storageKey) == AppAppearancePreference.system.rawValue)
        #expect(defaults.string(forKey: L10n.languageOverrideKey) == "zh-Hans")
    }
}

struct L10nCoverageTests {
    @Test
    func normalizedLanguageOverrideCodeCoversCommonMappings() {
        #expect(L10n.normalizedLanguageOverrideCode("") == L10n.systemLanguageCode)
        #expect(L10n.normalizedLanguageOverrideCode("system") == L10n.systemLanguageCode)
        #expect(L10n.normalizedLanguageOverrideCode("Follow System") == L10n.systemLanguageCode)
        #expect(L10n.normalizedLanguageOverrideCode(" zh-TW ") == "zh-Hant")
        #expect(L10n.normalizedLanguageOverrideCode("zh-HK") == "zh-Hant")
        #expect(L10n.normalizedLanguageOverrideCode("zh-SG") == "zh-Hans")
        #expect(L10n.normalizedLanguageOverrideCode("en-US") == "en")
        #expect(L10n.normalizedLanguageOverrideCode("fr-CA") == "fr")
        #expect(L10n.normalizedLanguageOverrideCode("es-MX") == "es")
        #expect(L10n.normalizedLanguageOverrideCode("ja-JP") == "ja")
        #expect(L10n.normalizedLanguageOverrideCode("ko-KR") == "ko")
        #expect(L10n.normalizedLanguageOverrideCode("unknown-language") == L10n.systemLanguageCode)
    }

    @Test
    func localeUsesExplicitOverrideThenFallback() {
        #expect(L10n.locale(for: "fr").identifier.hasPrefix("fr"))
        #expect(
            L10n.debugResolvedLanguageCode(
                selectedOverrideLanguageCode: "ja",
                preferredLanguages: ["en-US"]
            ) == "ja"
        )

        #expect(!L10n.locale(for: "unsupported").identifier.isEmpty)
    }

    @Test
    func textFallsBackToKeyForUnknownLocalizationKey() {
        let key = "l10n.coverage.unknown.\(UUID().uuidString)"
        #expect(L10n.text(key) == key)
    }

    @Test
    func resolvedLanguageCodePrefersOverrideThenPreferredLanguageMappings() {
        #expect(
            L10n.debugResolvedLanguageCode(
                selectedOverrideLanguageCode: "fr",
                preferredLanguages: ["zh-TW", "en-US"]
            ) == "fr"
        )

        #expect(
            L10n.debugResolvedLanguageCode(
                selectedOverrideLanguageCode: nil,
                preferredLanguages: ["zh-HK", "en-US"]
            ) == "zh-Hant"
        )

        #expect(
            L10n.debugResolvedLanguageCode(
                selectedOverrideLanguageCode: nil,
                preferredLanguages: ["zh-CN", "fr-FR"]
            ) == "zh-Hans"
        )

        #expect(
            L10n.debugResolvedLanguageCode(
                selectedOverrideLanguageCode: nil,
                preferredLanguages: ["es-MX", "fr-FR"]
            ) == "es"
        )

        #expect(
            L10n.debugResolvedLanguageCode(
                selectedOverrideLanguageCode: nil,
                preferredLanguages: ["xx-YY", "yy-ZZ"]
            ) == "en"
        )
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

    @Test
    func oauthLoginServiceSignInSupportsCancellationForCustomSchemeFlow() async {
        let service = OAuthLoginService(session: .shared)
        let config = OAuthClientConfiguration(
            issuer: URL(string: "https://auth.example.com")!,
            scopes: "openid profile email",
            redirectURI: "aiaagentpool://oauth/callback"
        )

        let task = Task {
            try await service.signIn(configuration: config)
        }

        try? await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected sign-in task to fail or cancel")
        } catch {
            #expect(task.isCancelled)
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

    @Test
    func desktopNotifierThrottleHookCoversSuppressionAndReset() {
        let sequence = PoolDashboardView.debugDesktopNotifierThrottleSequence(minInterval: 60)
        #expect(sequence.first)
        #expect(!sequence.second)
        #expect(sequence.afterReset)
    }
}

@Suite(.serialized)
@MainActor
struct WidgetBridgePublisherCoverageBoostTests {
    private func makeAccount(
        id: UUID = UUID(),
        name: String,
        usedUnits: Int,
        quota: Int,
        chatGPTAccountID: String,
        isPaid: Bool,
        isExcluded: Bool = false,
        primaryUsagePercent: Int? = nil
    ) -> AgentAccount {
        AgentAccount(
            id: id,
            name: name,
            usedUnits: usedUnits,
            quota: quota,
            apiToken: "token-\(name)",
            email: name,
            chatGPTAccountID: chatGPTAccountID,
            identityScope: AgentAccount.personalIdentityScope,
            primaryUsagePercent: primaryUsagePercent,
            isPaid: isPaid,
            isUsageSyncExcluded: isExcluded
        )
    }

    private func fetchBridgeResponse(
        maxAttempts: Int = 8,
        retryDelayNanoseconds: UInt64 = 150_000_000
    ) async throws -> (statusCode: Int, data: Data) {
        let url = try #require(URL(string: WidgetBridgePublisher.debugBridgeEndpoint()))
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 2
        var lastError: Error?

        for attempt in 0..<maxAttempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let http = try #require(response as? HTTPURLResponse)
                return (http.statusCode, data)
            } catch {
                lastError = error
                if attempt < (maxAttempts - 1) {
                    try await Task.sleep(nanoseconds: retryDelayNanoseconds)
                    continue
                }
                throw error
            }
        }

        throw lastError ?? URLError(.cannotLoadFromNetwork)
    }

    private func withIsolatedBridgePort(_ body: () async throws -> Void) async throws {
        let key = "WIDGET_BRIDGE_PORT"
        let original = ProcessInfo.processInfo.environment[key]
        let port = 39000 + Int(getpid() % 1000)
        setenv(key, String(port), 1)
        defer {
            if let original {
                setenv(key, original, 1)
            } else {
                unsetenv(key)
            }
        }

        try await body()
    }

    @Test
    func buildSnapshotComputesDeduplicatedPoolMetricsAndActiveSummary() {
        let activeID = UUID()
        let active = makeAccount(
            id: activeID,
            name: "paid@example.com",
            usedUnits: 30,
            quota: 100,
            chatGPTAccountID: "acct-paid",
            isPaid: true,
            primaryUsagePercent: 20
        )
        let duplicate = makeAccount(
            name: "paid-duplicate@example.com",
            usedUnits: 99,
            quota: 100,
            chatGPTAccountID: "acct-paid",
            isPaid: true,
            primaryUsagePercent: 90
        )
        let excluded = makeAccount(
            name: "excluded@example.com",
            usedUnits: 10,
            quota: 100,
            chatGPTAccountID: "acct-excluded",
            isPaid: false,
            isExcluded: true
        )

        var state = AccountPoolState(
            accounts: [active, duplicate, excluded],
            mode: .intelligent
        )
        state.markActiveAccountForSwitchLaunch(activeID)
        let snapshot = state.snapshot

        let now = Date(timeIntervalSince1970: 1_800_000)
        let rendered = WidgetBridgePublisher.debugBuildSnapshot(from: snapshot, updatedAt: now)

        #expect(rendered.updatedAt == now)
        #expect(rendered.mode == SwitchMode.intelligent.rawValue)
        #expect(rendered.totalAccounts == 1)
        #expect(rendered.availableAccounts == 1)
        #expect(rendered.overallUsagePercent == 30)
        #expect(rendered.activeAccountName == "paid@example.com")
        #expect(rendered.activeIsPaid == true)
        #expect(rendered.activeRemainingUnits == 70)
        #expect(rendered.activeQuota == 100)
        #expect(rendered.activeFiveHourRemainingPercent == 80)
        #expect(rendered.status == "Active: paid@example.com")
    }

    @Test
    func signatureAndThrottleHelpersBehaveDeterministically() {
        WidgetBridgePublisher.debugResetPublishState()

        let snapshot = WidgetBridgePublisher.Snapshot(
            updatedAt: Date(timeIntervalSince1970: 1_900_000),
            status: "Active: demo@example.com",
            source: "CodexPoolManager",
            mode: "intelligent",
            totalAccounts: 3,
            availableAccounts: 2,
            overallUsagePercent: 55,
            activeAccountName: "demo@example.com",
            activeIsPaid: true,
            activeRemainingUnits: 45,
            activeQuota: 100,
            activeFiveHourRemainingPercent: 72,
            activeWeeklyResetAt: Date(timeIntervalSince1970: 1_900_800),
            activeFiveHourResetAt: Date(timeIntervalSince1970: 1_900_200)
        )

        let signature = WidgetBridgePublisher.debugSnapshotSignature(for: snapshot)
        #expect(!signature.isEmpty)

        let now = Date(timeIntervalSince1970: 2_000_000)
        #expect(!WidgetBridgePublisher.debugShouldThrottle(signature: signature, now: now))
        WidgetBridgePublisher.debugMarkPublished(signature: signature, at: now)
        #expect(WidgetBridgePublisher.debugShouldThrottle(signature: signature, now: now.addingTimeInterval(5)))
        #expect(!WidgetBridgePublisher.debugShouldThrottle(signature: signature, now: now.addingTimeInterval(11)))

        WidgetBridgePublisher.debugResetPublishState()
        #expect(!WidgetBridgePublisher.debugShouldThrottle(signature: signature, now: now))
    }

    @Test
    func uniqueAccountHelperPreservesFirstSeenOrderByDedupKey() {
        let first = makeAccount(
            name: "first@example.com",
            usedUnits: 10,
            quota: 100,
            chatGPTAccountID: "same-id",
            isPaid: false
        )
        let secondDuplicate = makeAccount(
            name: "second@example.com",
            usedUnits: 80,
            quota: 100,
            chatGPTAccountID: "same-id",
            isPaid: true
        )
        let third = makeAccount(
            name: "third@example.com",
            usedUnits: 50,
            quota: 100,
            chatGPTAccountID: "third-id",
            isPaid: false
        )

        let keys = WidgetBridgePublisher.debugUniqueAccountDedupKeys(from: [first, secondDuplicate, third])
        #expect(keys.count == 2)
        #expect(keys[0] == first.deduplicationKey)
        #expect(keys[1] == third.deduplicationKey)
    }

    @Test
    func localBridgeServerReturnsNoContentBeforePublishAndJSONAfterPublish() async throws {
        try await withIsolatedBridgePort {
            WidgetBridgePublisher.debugResetPublishState()
            WidgetBridgePublisher.debugResetBridgeServerState()
            WidgetBridgePublisher.configureBridge()
            try await Task.sleep(nanoseconds: 200_000_000)

            let expectedStatus = "Active: bridge-\(UUID().uuidString)"
            WidgetBridgePublisher.publishFromMainApp(status: expectedStatus)
            try await Task.sleep(nanoseconds: 200_000_000)

            let populatedResponse = try await fetchBridgeResponse()
            #expect(populatedResponse.statusCode == 200)
            #expect(!populatedResponse.data.isEmpty)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(WidgetBridgePublisher.Snapshot.self, from: populatedResponse.data)
            #expect(snapshot.status == expectedStatus)
            #expect(snapshot.source == "CodexPoolManager")
        }
    }

    @Test
    func bridgeResponseEncodingCoversNoContentAndContentPaths() throws {
        let emptyResponse = WidgetBridgePublisher.debugHTTPBridgeResponse(payload: Data())
        let emptyText = try #require(String(data: emptyResponse, encoding: .utf8))
        #expect(emptyText.contains("HTTP/1.1 204 No Content"))
        #expect(emptyText.contains("Content-Length: 0"))

        let payload = Data("{\"status\":\"ok\"}".utf8)
        let populatedResponse = WidgetBridgePublisher.debugHTTPBridgeResponse(payload: payload)
        let populatedPrefix = try #require(String(data: populatedResponse.prefix(80), encoding: .utf8))
        #expect(populatedPrefix.contains("HTTP/1.1 200 OK"))
        #expect(populatedPrefix.contains("Content-Type: application/json"))
        #expect(populatedResponse.suffix(payload.count) == payload)
    }

    @Test
    func previewModeSkipsPublishingToBridgeServer() async throws {
        WidgetBridgePublisher.debugResetPublishState()

        let baseline = Date()
        let expectedSignature = WidgetBridgePublisher.debugSnapshotSignature(
            for: WidgetBridgePublisher.Snapshot(
                updatedAt: baseline,
                status: "should-not-publish",
                source: "CodexPoolManager",
                mode: nil,
                totalAccounts: nil,
                availableAccounts: nil,
                overallUsagePercent: nil,
                activeAccountName: nil,
                activeIsPaid: nil,
                activeRemainingUnits: nil,
                activeQuota: nil,
                activeFiveHourRemainingPercent: nil,
                activeWeeklyResetAt: nil,
                activeFiveHourResetAt: nil
            )
        )

        #expect(!WidgetBridgePublisher.debugShouldThrottle(signature: expectedSignature, now: baseline))

        WidgetBridgePublisher.debugPublishFromMainApp(
            status: "should-not-publish",
            environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"]
        )

        #expect(!WidgetBridgePublisher.debugShouldThrottle(signature: expectedSignature, now: baseline))
    }
}

#if canImport(AppKit)
@MainActor
struct CodexAuthFilePanelServiceDebugOverrideTests {
    @Test
    func defaultInitializerUsesDefaultPickerOverrideWhenPresent() {
        let expectedURL = URL(fileURLWithPath: "/tmp/auth-\(UUID().uuidString).json")
        CodexAuthFilePanelService.defaultPickerOverride = { expectedURL }
        defer { CodexAuthFilePanelService.defaultPickerOverride = nil }

        let service = CodexAuthFilePanelService()
        #expect(service.pickAuthFileURL() == expectedURL)
    }

    @Test
    func pickURLFromPanelUsesRunModalOverrideWhenExplicitClosureMissing() {
        let panel = NSOpenPanel()
        var overrideCalled = false
        CodexAuthFilePanelService.runModalOverride = { _ in
            overrideCalled = true
            return .cancel
        }
        defer { CodexAuthFilePanelService.runModalOverride = nil }

        let selectedURL = CodexAuthFilePanelService.pickURLFromPanel(panel)
        #expect(overrideCalled)
        #expect(selectedURL == nil)
    }

    @Test
    func explicitRunModalClosureTakesPrecedenceOverOverride() {
        let panel = NSOpenPanel()
        var overrideCalled = false
        var explicitCalled = false

        CodexAuthFilePanelService.runModalOverride = { _ in
            overrideCalled = true
            return .cancel
        }
        defer { CodexAuthFilePanelService.runModalOverride = nil }

        _ = CodexAuthFilePanelService.pickURLFromPanel(panel) { _ in
            explicitCalled = true
            return .OK
        }

        #expect(explicitCalled)
        #expect(!overrideCalled)
    }
}
#endif
