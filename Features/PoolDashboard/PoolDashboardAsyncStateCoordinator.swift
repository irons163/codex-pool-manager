import Foundation

struct PoolDashboardAsyncStateCoordinator {
    func beginUsageSync(viewState: inout PoolDashboardViewState) -> Bool {
        begin(
            isRunning: viewState.isSyncingUsage,
            setRunning: { viewState.isSyncingUsage = $0 }
        )
    }

    func endUsageSync(viewState: inout PoolDashboardViewState) {
        viewState.isSyncingUsage = false
    }

    func beginOAuthSignIn(viewState: inout PoolDashboardViewState) -> Bool {
        begin(
            isRunning: viewState.isSigningInOAuth,
            setRunning: { viewState.isSigningInOAuth = $0 },
            onStart: {
                viewState.oauthError = nil
                viewState.oauthSuccessMessage = nil
            }
        )
    }

    func endOAuthSignIn(viewState: inout PoolDashboardViewState) {
        viewState.isSigningInOAuth = false
    }

    private func begin(
        isRunning: Bool,
        setRunning: (Bool) -> Void,
        onStart: () -> Void = {}
    ) -> Bool {
        guard !isRunning else { return false }
        setRunning(true)
        onStart()
        return true
    }
}
