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
        clearOAuthMessages(viewState: &viewState)
        return true
    }

    func endOAuthSignIn(viewState: inout PoolDashboardViewState) {
        viewState.isSigningInOAuth = false
    }

    private func clearOAuthMessages(viewState: inout PoolDashboardViewState) {
        viewState.oauthError = nil
        viewState.oauthSuccessMessage = nil
    }
}
