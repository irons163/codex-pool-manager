import Foundation

struct PoolDashboardOAuthSignInFlowCoordinator {
    struct Input {
        let issuer: String
        let clientID: String
        let scopes: String
        let redirectURI: String
        let originator: String
        let workspaceID: String
        let fallbackQuota: Int
    }

    struct Output {
        let state: AccountPoolState
        let viewState: PoolDashboardViewState
        let oauthAccountName: String
        let shouldRefreshLocalOAuthAccounts: Bool
    }

    private let runtimeCoordinator = PoolDashboardRuntimeCoordinator()
    private let mutationCoordinator = PoolDashboardMutationCoordinator()

    func signInWithOAuth(
        from state: AccountPoolState,
        viewState: PoolDashboardViewState,
        oauthAccountName: String,
        input: Input
    ) async -> Output {
        var nextState = state
        var nextViewState = viewState
        var nextOAuthAccountName = oauthAccountName

        let runtimeOutput = await runtimeCoordinator.signInWithOAuth(
            from: state,
            input: makeRuntimeInput(input, oauthAccountName: oauthAccountName)
        )
        let shouldRefreshLocalOAuthAccounts = mutationCoordinator.applyOAuthOutput(
            runtimeOutput,
            state: &nextState,
            viewState: &nextViewState,
            oauthAccountName: &nextOAuthAccountName
        )

        return Output(
            state: nextState,
            viewState: nextViewState,
            oauthAccountName: nextOAuthAccountName,
            shouldRefreshLocalOAuthAccounts: shouldRefreshLocalOAuthAccounts
        )
    }

    private func makeRuntimeInput(
        _ input: Input,
        oauthAccountName: String
    ) -> PoolDashboardRuntimeCoordinator.OAuthSignInInput {
        .init(
            issuer: input.issuer,
            clientID: input.clientID,
            scopes: input.scopes,
            redirectURI: input.redirectURI,
            originator: input.originator,
            workspaceID: input.workspaceID,
            accountNameInput: oauthAccountName,
            fallbackQuota: input.fallbackQuota
        )
    }
}
