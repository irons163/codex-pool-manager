import Foundation

struct PoolDashboardAsyncStateCoordinator {
    func beginUsageSync(
        viewState: inout PoolDashboardViewState,
        now: Date = .now
    ) -> Bool {
        guard !viewState.isSyncingUsage else { return false }
        viewState.isSyncingUsage = true
        viewState.usageSyncStartedAt = now
        viewState.syncError = nil
        return true
    }

    func endUsageSync(viewState: inout PoolDashboardViewState) {
        viewState.isSyncingUsage = false
        viewState.usageSyncStartedAt = nil
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
