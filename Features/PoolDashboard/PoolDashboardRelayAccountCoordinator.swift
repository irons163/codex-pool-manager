import Foundation

struct PoolDashboardRelayAccountCoordinator {
    typealias AppRelauncher = @MainActor (
        _ launchTarget: CodexLaunchTarget
    ) async throws -> Bool
    typealias EnhancedConfigApplier = (
        _ provider: CodexProviderConfig,
        _ apiKey: String
    ) throws -> Void
    typealias RelayHistoryMigrator = (
        _ sourceProviderID: String
    ) async throws -> CodexRelayHistoryBucketMigrationOutcome

    struct AddOutput {
        let state: AccountPoolState
        let viewState: PoolDashboardViewState
    }

    struct SwitchOutput {
        let viewState: PoolDashboardViewState
        let didSwitchAuth: Bool
    }

    private let configApplier: (CodexProviderConfig) throws -> Void
    private let enhancedConfigApplier: EnhancedConfigApplier
    private let historyMigrator: RelayHistoryMigrator
    private let apiKeyLogin: (String) async throws -> Void
    private let appRelauncher: AppRelauncher

    init(
        configApplier: @escaping (CodexProviderConfig) throws -> Void = { try CodexProviderConfigService().apply($0) },
        enhancedConfigApplier: @escaping EnhancedConfigApplier = { provider, apiKey in
            try CodexProviderConfigService().applyPreservingOfficialAuth(provider, apiKey: apiKey)
        },
        historyMigrator: @escaping RelayHistoryMigrator = { sourceProviderID in
            try await Task.detached(priority: .utility) {
                try CodexRelayHistoryBucketMigrationService().migrate(sourceProviderID: sourceProviderID)
            }.value
        },
        apiKeyLogin: @escaping (String) async throws -> Void = { try await CodexAPIKeyLoginService().login(apiKey: $0) },
        appRelauncher: @escaping AppRelauncher = Self.defaultAppRelauncher
    ) {
        self.configApplier = configApplier
        self.enhancedConfigApplier = enhancedConfigApplier
        self.historyMigrator = historyMigrator
        self.apiKeyLogin = apiKeyLogin
        self.appRelauncher = appRelauncher
    }

    func addRelayAccount(
        to state: AccountPoolState,
        viewState: PoolDashboardViewState,
        name: String,
        providerID: String,
        providerName: String,
        baseURL: String,
        wireAPI: String,
        apiKey: String
    ) async -> AddOutput {
        var nextState = state
        var nextViewState = viewState

        do {
            let provider = try CodexProviderConfig(
                providerID: providerID,
                name: providerName,
                baseURL: baseURL,
                wireAPI: wireAPI
            )
            let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let accountID = nextState.addAccount(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.name : name,
                quota: 100,
                usedUnits: 0,
                apiToken: trimmedAPIKey,
                credentialType: .relayAPIKey,
                relayProviderID: provider.providerID,
                relayProviderName: provider.name,
                relayBaseURL: provider.baseURL.absoluteString,
                relayWireAPI: provider.wireAPI,
                relayRequiresOpenAIAuth: provider.requiresOpenAIAuth
            )
            nextState.setUsageSyncExclusion(
                for: accountID,
                reason: AgentAccount.relayUsageSyncUnavailableReason
            )
            nextViewState.relayError = nil
            nextViewState.relaySuccessMessage = L10n.text("relay.status.added")
        } catch {
            nextViewState.relaySuccessMessage = nil
            nextViewState.relayError = error.localizedDescription
        }

        return AddOutput(state: nextState, viewState: nextViewState)
    }

    @MainActor
    func switchToRelayAccount(
        _ account: AgentAccount,
        switchWithoutLaunching: Bool = false,
        preserveOfficialAuth: Bool = false,
        launchTarget: CodexLaunchTarget = .auto,
        viewState: PoolDashboardViewState
    ) async -> SwitchOutput {
        var nextViewState = viewState
        var logLines = [L10n.text("relay.switch.start_format", account.name)]

        do {
            guard account.isRelayAPIKeyAccount else {
                throw CodexProviderConfigError.invalidProviderID
            }
            let apiKey = account.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !apiKey.isEmpty else {
                throw CodexAPIKeyLoginError.loginFailed(L10n.text("relay.error.missing_api_key"))
            }
            let provider = try CodexProviderConfig(
                providerID: account.relayProviderID ?? "",
                name: account.relayProviderName ?? account.relayProviderID ?? "",
                baseURL: account.relayBaseURL ?? "",
                wireAPI: account.relayWireAPI ?? AgentAccount.defaultRelayWireAPI,
                requiresOpenAIAuth: account.relayRequiresOpenAIAuth
            )

            if preserveOfficialAuth {
                try enhancedConfigApplier(provider, apiKey)
            } else {
                try configApplier(provider)
            }
            logLines.append(L10n.text("relay.switch.config_updated_format", provider.providerID))
            if preserveOfficialAuth {
                logLines.append(L10n.text("relay.switch.preserve_official_auth_enabled"))
                do {
                    let outcome = try await historyMigrator(provider.providerID)
                    if outcome.didMigrate {
                        logLines.append(
                            L10n.text(
                                "relay.switch.history_bucket_migrated_format",
                                provider.providerID,
                                CodexProviderConfig.relayHistoryBucketProviderID,
                                outcome.migratedSessionFiles,
                                outcome.migratedThreadRows
                            )
                        )
                    }
                } catch {
                    logLines.append(
                        L10n.text("relay.switch.history_bucket_failed_format", error.localizedDescription)
                    )
                }
            } else {
                try await apiKeyLogin(apiKey)
                logLines.append(L10n.text("relay.switch.login_completed"))
            }
            nextViewState.switchLaunchError = nil
            nextViewState.switchLaunchWarning = nil
        } catch {
            logLines.append(L10n.text("relay.switch.failed_format", error.localizedDescription))
            nextViewState.switchLaunchError = error.localizedDescription
            nextViewState.switchLaunchWarning = nil
            nextViewState.lastSwitchLaunchLog = logLines.joined(separator: "\n")
            return SwitchOutput(viewState: nextViewState, didSwitchAuth: false)
        }

        if switchWithoutLaunching {
            logLines.append(L10n.text("switch.service.log.launch_skipped_by_setting"))
        } else {
            do {
                let launchedImmediately = try await appRelauncher(launchTarget)
                if launchedImmediately {
                    logLines.append(L10n.text("switch.service.log.launch_completed"))
                } else {
                    logLines.append("Launch is deferred. Waiting for app to close, then will relaunch automatically.")
                }
            } catch {
                logLines.append(L10n.text("relay.switch.failed_format", error.localizedDescription))
                nextViewState.switchLaunchError = nil
                nextViewState.switchLaunchWarning = L10n.text("switch.warning.launch_failed_but_switched")
            }
        }

        nextViewState.lastSwitchLaunchLog = logLines.joined(separator: "\n")
        return SwitchOutput(viewState: nextViewState, didSwitchAuth: true)
    }

    @MainActor
    private static func defaultAppRelauncher(
        launchTarget: CodexLaunchTarget
    ) async throws -> Bool {
        try await CodexAuthSwitchService().performLaunchAfterExternalAuthSwitch(launchTarget: launchTarget)
    }
}
