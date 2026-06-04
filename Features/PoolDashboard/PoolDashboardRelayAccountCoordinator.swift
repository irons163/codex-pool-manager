import Foundation

struct PoolDashboardRelayAccountCoordinator {
    struct AddOutput {
        let state: AccountPoolState
        let viewState: PoolDashboardViewState
    }

    struct SwitchOutput {
        let viewState: PoolDashboardViewState
    }

    private let configApplier: (CodexProviderConfig) throws -> Void
    private let apiKeyLogin: (String) async throws -> Void

    init(
        configApplier: @escaping (CodexProviderConfig) throws -> Void = { try CodexProviderConfigService().apply($0) },
        apiKeyLogin: @escaping (String) async throws -> Void = { try await CodexAPIKeyLoginService().login(apiKey: $0) }
    ) {
        self.configApplier = configApplier
        self.apiKeyLogin = apiKeyLogin
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

    func switchToRelayAccount(_ account: AgentAccount, viewState: PoolDashboardViewState) async -> SwitchOutput {
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

            try configApplier(provider)
            logLines.append(L10n.text("relay.switch.config_updated_format", provider.providerID))
            try await apiKeyLogin(apiKey)
            logLines.append(L10n.text("relay.switch.login_completed"))
            nextViewState.switchLaunchError = nil
            nextViewState.switchLaunchWarning = nil
        } catch {
            logLines.append(L10n.text("relay.switch.failed_format", error.localizedDescription))
            nextViewState.switchLaunchError = error.localizedDescription
        }

        nextViewState.lastSwitchLaunchLog = logLines.joined(separator: "\n")
        return SwitchOutput(viewState: nextViewState)
    }
}
