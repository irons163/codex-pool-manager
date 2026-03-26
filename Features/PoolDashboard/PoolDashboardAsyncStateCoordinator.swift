import Foundation

struct PoolDashboardAsyncStateCoordinator {
    func beginUsageSync(viewState: inout PoolDashboardViewState) -> Bool {
        guard !viewState.isSyncingUsage else { return false }
        viewState.isSyncingUsage = true
        return true
    }

    func endUsageSync(viewState: inout PoolDashboardViewState) {
        viewState.isSyncingUsage = false
    }

    func beginOAuthSignIn(viewState: inout PoolDashboardViewState) -> Bool {
        guard !viewState.isSigningInOAuth else { return false }
        viewState.isSigningInOAuth = true
        viewState.oauthError = nil
        viewState.oauthSuccessMessage = nil
        return true
    }

    func endOAuthSignIn(viewState: inout PoolDashboardViewState) {
        viewState.isSigningInOAuth = false
    }
}
