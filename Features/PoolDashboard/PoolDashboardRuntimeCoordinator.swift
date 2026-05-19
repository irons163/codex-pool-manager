import Foundation

protocol PoolDashboardDataFlowCoordinating {
    func syncState(
        from state: AccountPoolState
    ) async throws -> (state: AccountPoolState, rawResponse: String?)
}

extension PoolDashboardDataFlowCoordinator: PoolDashboardDataFlowCoordinating {}

protocol PoolDashboardAuthFlowCoordinating {
    func buildConfiguration(
        issuer: String,
        clientID: String,
        scopes: String,
        redirectURI: String,
        originator: String,
        workspaceID: String
    ) throws -> OAuthClientConfiguration

    func fetchOAuthSignInContext(
        configuration: OAuthClientConfiguration,
        loginService: OAuthLoginServicing,
        usageClient: CodexUsageFetching
    ) async throws -> PoolDashboardAuthFlowCoordinator.OAuthSignInContext

    func makeOAuthSignInContext(
        tokens: OAuthTokens,
        usageClient: CodexUsageFetching,
        fallbackWorkspaceID: String?
    ) async -> PoolDashboardAuthFlowCoordinator.OAuthSignInContext

    func applyOAuthSignIn(
        state: inout AccountPoolState,
        context: PoolDashboardAuthFlowCoordinator.OAuthSignInContext,
        accountNameInput: String,
        fallbackQuota: Int
    ) -> String
}

extension PoolDashboardAuthFlowCoordinator: PoolDashboardAuthFlowCoordinating {}

protocol OAuthManualSignInServicing {
    func prepareManualSignIn(configuration: OAuthClientConfiguration) throws -> OAuthManualSignInPreparation

    func completeManualSignIn(
        configuration: OAuthClientConfiguration,
        callbackURL: URL,
        expectedState: String,
        codeVerifier: String
    ) async throws -> OAuthTokens
}

typealias OAuthCompleteLoginServicing = OAuthLoginServicing & OAuthManualSignInServicing

extension OAuthLoginService: OAuthManualSignInServicing {}

struct PoolDashboardRuntimeCoordinator {
    private enum Message {
        static let syncFailurePrefix = "sync.failure.prefix"
    }

    struct SyncOutput {
        let state: AccountPoolState
        let syncError: String?
        let lastUsageRawJSON: String?
    }

    struct OAuthSignInInput {
        let issuer: String
        let clientID: String
        let scopes: String
        let redirectURI: String
        let originator: String
        let workspaceID: String
        let accountNameInput: String
        let fallbackQuota: Int
    }

    struct OAuthSignInOutput {
        let state: AccountPoolState
        let oauthError: String?
        let oauthSuccessMessage: String?
        let nextOAuthAccountName: String
        let shouldRefreshLocalOAuthAccounts: Bool
    }

    struct ManualOAuthPreparationOutput {
        let authorizationURL: URL?
        let expectedState: String?
        let codeVerifier: String?
        let oauthError: String?
    }

    private let authFlowCoordinator: PoolDashboardAuthFlowCoordinating
    private let dataFlowCoordinator: PoolDashboardDataFlowCoordinating
    private let loginServiceFactory: (() -> OAuthCompleteLoginServicing)?
    private let usageClientFactory: (() -> CodexUsageFetching)?

    init(
        authFlowCoordinator: PoolDashboardAuthFlowCoordinating = PoolDashboardAuthFlowCoordinator(),
        dataFlowCoordinator: PoolDashboardDataFlowCoordinating = PoolDashboardDataFlowCoordinator(),
        loginServiceFactory: (() -> OAuthCompleteLoginServicing)? = nil,
        usageClientFactory: (() -> CodexUsageFetching)? = nil
    ) {
        self.authFlowCoordinator = authFlowCoordinator
        self.dataFlowCoordinator = dataFlowCoordinator
        self.loginServiceFactory = loginServiceFactory
        self.usageClientFactory = usageClientFactory
    }

    func syncCodexUsage(from state: AccountPoolState) async -> SyncOutput {
        do {
            let (syncedState, rawResponse) = try await dataFlowCoordinator.syncState(from: state)
            return SyncOutput(
                state: syncedState,
                syncError: nil,
                lastUsageRawJSON: rawResponse
            )
        } catch {
            return syncFailureOutput(from: state, error: error)
        }
    }

    func signInWithOAuth(
        from state: AccountPoolState,
        input: OAuthSignInInput
    ) async -> OAuthSignInOutput {
        do {
            let oauthConfiguration = try makeOAuthConfiguration(input: input)
            let loginService = loginServiceFactory?() ?? OAuthLoginService()

            let context = try await authFlowCoordinator.fetchOAuthSignInContext(
                configuration: oauthConfiguration,
                loginService: loginService,
                usageClient: usageClientFactory?() ?? OpenAICodexUsageClient()
            )

            var nextState = state
            let successMessage = authFlowCoordinator.applyOAuthSignIn(
                state: &nextState,
                context: context,
                accountNameInput: input.accountNameInput,
                fallbackQuota: input.fallbackQuota
            )

            return oauthSuccessOutput(
                state: nextState,
                successMessage: successMessage
            )
        } catch {
            return oauthFailureOutput(
                state: state,
                accountNameInput: input.accountNameInput,
                error: error
            )
        }
    }

    func prepareManualOAuthSignIn(
        input: OAuthSignInInput
    ) -> ManualOAuthPreparationOutput {
        do {
            let oauthConfiguration = try makeOAuthConfiguration(input: input)
            let preparation = try (loginServiceFactory?() ?? OAuthLoginService())
                .prepareManualSignIn(configuration: oauthConfiguration)
            return ManualOAuthPreparationOutput(
                authorizationURL: preparation.authorizationURL,
                expectedState: preparation.state,
                codeVerifier: preparation.codeVerifier,
                oauthError: nil
            )
        } catch {
            return ManualOAuthPreparationOutput(
                authorizationURL: nil,
                expectedState: nil,
                codeVerifier: nil,
                oauthError: error.localizedDescription
            )
        }
    }

    func importManualOAuthCallback(
        from state: AccountPoolState,
        input: OAuthSignInInput,
        callbackURLString: String,
        expectedState: String,
        codeVerifier: String
    ) async -> OAuthSignInOutput {
        do {
            let oauthConfiguration = try makeOAuthConfiguration(input: input)
            let loginService = loginServiceFactory?() ?? OAuthLoginService()
            let trimmedCallbackURL = callbackURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let callbackURL = URL(string: trimmedCallbackURL), !trimmedCallbackURL.isEmpty else {
                throw OAuthLoginError.invalidCallback
            }

            let tokens = try await loginService.completeManualSignIn(
                configuration: oauthConfiguration,
                callbackURL: callbackURL,
                expectedState: expectedState,
                codeVerifier: codeVerifier
            )

            let context = await authFlowCoordinator.makeOAuthSignInContext(
                tokens: tokens,
                usageClient: usageClientFactory?() ?? OpenAICodexUsageClient(),
                fallbackWorkspaceID: oauthConfiguration.forcedWorkspaceID
            )

            var nextState = state
            let successMessage = authFlowCoordinator.applyOAuthSignIn(
                state: &nextState,
                context: context,
                accountNameInput: input.accountNameInput,
                fallbackQuota: input.fallbackQuota
            )

            return oauthSuccessOutput(
                state: nextState,
                successMessage: successMessage
            )
        } catch {
            return oauthFailureOutput(
                state: state,
                accountNameInput: input.accountNameInput,
                error: error
            )
        }
    }

    private func syncFailureOutput(from state: AccountPoolState, error: Error) -> SyncOutput {
        SyncOutput(
            state: state,
            syncError: L10n.text("sync.failure.with_description_format", L10n.text(Message.syncFailurePrefix), error.localizedDescription),
            lastUsageRawJSON: nil
        )
    }

    private func oauthSuccessOutput(
        state: AccountPoolState,
        successMessage: String
    ) -> OAuthSignInOutput {
        OAuthSignInOutput(
            state: state,
            oauthError: nil,
            oauthSuccessMessage: successMessage,
            nextOAuthAccountName: "",
            shouldRefreshLocalOAuthAccounts: true
        )
    }

    private func oauthFailureOutput(
        state: AccountPoolState,
        accountNameInput: String,
        error: Error
    ) -> OAuthSignInOutput {
        OAuthSignInOutput(
            state: state,
            oauthError: error.localizedDescription,
            oauthSuccessMessage: nil,
            nextOAuthAccountName: accountNameInput,
            shouldRefreshLocalOAuthAccounts: false
        )
    }

    private func makeOAuthConfiguration(
        input: OAuthSignInInput
    ) throws -> OAuthClientConfiguration {
        try authFlowCoordinator.buildConfiguration(
            issuer: input.issuer,
            clientID: input.clientID,
            scopes: input.scopes,
            redirectURI: input.redirectURI,
            originator: input.originator,
            workspaceID: input.workspaceID
        )
    }
}
