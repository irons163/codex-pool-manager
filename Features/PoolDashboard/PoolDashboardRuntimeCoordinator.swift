import Foundation

struct PoolDashboardRuntimeCoordinator {
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

    private let authFlowCoordinator = PoolDashboardAuthFlowCoordinator()
    private let dataFlowCoordinator = PoolDashboardDataFlowCoordinator()

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
            let oauthConfiguration = try authFlowCoordinator.buildConfiguration(
                issuer: input.issuer,
                clientID: input.clientID,
                scopes: input.scopes,
                redirectURI: input.redirectURI,
                originator: input.originator,
                workspaceID: input.workspaceID
            )

            let context = try await authFlowCoordinator.fetchOAuthSignInContext(
                configuration: oauthConfiguration,
                loginService: OAuthLoginService(),
                usageClient: OpenAICodexUsageClient()
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
            syncError: "同步失敗：\(error.localizedDescription)",
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
}
