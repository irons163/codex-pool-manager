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
            let result = try await dataFlowCoordinator.syncState(from: state)
            return SyncOutput(
                state: result.state,
                syncError: nil,
                lastUsageRawJSON: result.rawResponse
            )
        } catch {
            return SyncOutput(
                state: state,
                syncError: makeSyncFailureMessage(from: error),
                lastUsageRawJSON: nil
            )
        }
    }

    func signInWithOAuth(
        from state: AccountPoolState,
        input: OAuthSignInInput
    ) async -> OAuthSignInOutput {
        do {
            let configuration = try authFlowCoordinator.buildConfiguration(
                issuer: input.issuer,
                clientID: input.clientID,
                scopes: input.scopes,
                redirectURI: input.redirectURI,
                originator: input.originator,
                workspaceID: input.workspaceID
            )

            let context = try await authFlowCoordinator.fetchOAuthSignInContext(
                configuration: configuration,
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

            return OAuthSignInOutput(
                state: nextState,
                oauthError: nil,
                oauthSuccessMessage: successMessage,
                nextOAuthAccountName: "",
                shouldRefreshLocalOAuthAccounts: true
            )
        } catch {
            return OAuthSignInOutput(
                state: state,
                oauthError: error.localizedDescription,
                oauthSuccessMessage: nil,
                nextOAuthAccountName: input.accountNameInput,
                shouldRefreshLocalOAuthAccounts: false
            )
        }
    }

    private func makeSyncFailureMessage(from error: Error) -> String {
        "同步失敗：\(error.localizedDescription)"
    }
}
