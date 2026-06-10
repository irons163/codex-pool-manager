import Foundation

struct PoolDashboardRelayAccountCoordinator {
    typealias AppRelauncher = @MainActor (
        _ launchTarget: CodexLaunchTarget
    ) async throws -> Bool
    typealias EnhancedConfigApplier = (
        _ provider: CodexProviderConfig,
        _ apiKey: String
    ) throws -> Void
    typealias APIKeyLogin = (Data) async throws -> Void

    struct AddOutput {
        let state: AccountPoolState
        let viewState: PoolDashboardViewState
    }

    struct SwitchOutput {
        let viewState: PoolDashboardViewState
        let didSwitchAuth: Bool
    }

    struct SwitchRequest {
        let accountID: UUID
        let accountName: String
        let provider: CodexProviderConfig
        let apiKey: String
        let apiKeyData: Data

        init(account: AgentAccount, fallbackAPIKey: String? = nil) throws {
            guard account.isRelayAPIKeyAccount else {
                throw CodexProviderConfigError.invalidProviderID
            }

            let accountAPIKey = Self.trimmedStableCopy(account.apiToken)
            let fallbackAPIKey = Self.trimmedStableCopy(fallbackAPIKey ?? "")
            let apiKey = accountAPIKey.isEmpty ? fallbackAPIKey : accountAPIKey
            guard !apiKey.isEmpty else {
                throw CodexAPIKeyLoginError.loginFailed(L10n.text("relay.error.missing_api_key"))
            }

            accountID = account.id
            accountName = Self.stableCopy(account.name)
            self.apiKey = apiKey
            apiKeyData = Data(Array(apiKey.utf8))
            provider = try CodexProviderConfig(
                providerID: Self.stableCopy(account.relayProviderID ?? ""),
                name: Self.stableCopy(account.relayProviderName ?? account.relayProviderID ?? ""),
                baseURL: Self.stableCopy(account.relayBaseURL ?? ""),
                wireAPI: Self.stableCopy(account.relayWireAPI ?? AgentAccount.defaultRelayWireAPI),
                requiresOpenAIAuth: account.relayRequiresOpenAIAuth
            )
        }

        private static func trimmedStableCopy(_ value: String) -> String {
            stableCopy(value).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private static func stableCopy(_ value: String) -> String {
            String(decoding: Array(value.utf8), as: UTF8.self)
        }
    }

    private let configApplier: (CodexProviderConfig) throws -> Void
    private let enhancedConfigApplier: EnhancedConfigApplier
    private let apiKeyLogin: APIKeyLogin
    private let appRelauncher: AppRelauncher

    init(
        configApplier: @escaping (CodexProviderConfig) throws -> Void = { try CodexProviderConfigService().apply($0) },
        enhancedConfigApplier: @escaping EnhancedConfigApplier = { provider, apiKey in
            try CodexProviderConfigService().applyPreservingOfficialAuth(provider, apiKey: apiKey)
        },
        apiKeyLogin: @escaping APIKeyLogin = { try await CodexAPIKeyLoginService().login(trimmedAPIKeyData: $0) },
        appRelauncher: @escaping AppRelauncher = Self.defaultAppRelauncher
    ) {
        self.configApplier = configApplier
        self.enhancedConfigApplier = enhancedConfigApplier
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
        _ request: SwitchRequest,
        switchWithoutLaunching: Bool = false,
        preserveOfficialAuth: Bool = false,
        launchTarget: CodexLaunchTarget = .auto,
        viewState: PoolDashboardViewState
    ) async -> SwitchOutput {
        var nextViewState = viewState
        var logLines = [L10n.text("relay.switch.start_format", request.accountName)]

        do {
            let provider = request.provider

            if preserveOfficialAuth {
                try enhancedConfigApplier(provider, request.apiKey)
            } else {
                try configApplier(provider)
            }
            logLines.append(L10n.text("relay.switch.config_updated_format", provider.providerID))
            if preserveOfficialAuth {
                logLines.append(L10n.text("relay.switch.preserve_official_auth_enabled"))
                try await apiKeyLogin(request.apiKeyData)
                logLines.append(L10n.text("relay.switch.login_completed"))
            } else {
                try await apiKeyLogin(request.apiKeyData)
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
