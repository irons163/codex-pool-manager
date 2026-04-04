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

    struct ManualPreparationOutput {
        let authorizationURL: URL?
        let expectedState: String?
        let codeVerifier: String?
        let oauthError: String?
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
            input: input.runtimeInput(accountNameInput: oauthAccountName)
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

    func prepareManualOAuthSignIn(
        input: Input
    ) -> ManualPreparationOutput {
        let runtimeOutput = runtimeCoordinator.prepareManualOAuthSignIn(
            input: input.runtimeInput(accountNameInput: "")
        )
        return ManualPreparationOutput(
            authorizationURL: runtimeOutput.authorizationURL,
            expectedState: runtimeOutput.expectedState,
            codeVerifier: runtimeOutput.codeVerifier,
            oauthError: runtimeOutput.oauthError
        )
    }

    func importManualOAuthCallback(
        from state: AccountPoolState,
        viewState: PoolDashboardViewState,
        oauthAccountName: String,
        input: Input,
        callbackURLString: String,
        expectedState: String,
        codeVerifier: String
    ) async -> Output {
        var nextState = state
        var nextViewState = viewState
        var nextOAuthAccountName = oauthAccountName

        let runtimeOutput = await runtimeCoordinator.importManualOAuthCallback(
            from: state,
            input: input.runtimeInput(accountNameInput: oauthAccountName),
            callbackURLString: callbackURLString,
            expectedState: expectedState,
            codeVerifier: codeVerifier
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
}

private extension PoolDashboardOAuthSignInFlowCoordinator.Input {
    func runtimeInput(accountNameInput: String) -> PoolDashboardRuntimeCoordinator.OAuthSignInInput {
        .init(
            issuer: issuer,
            clientID: clientID,
            scopes: scopes,
            redirectURI: redirectURI,
            originator: originator,
            workspaceID: workspaceID,
            accountNameInput: accountNameInput,
            fallbackQuota: fallbackQuota
        )
    }
}
