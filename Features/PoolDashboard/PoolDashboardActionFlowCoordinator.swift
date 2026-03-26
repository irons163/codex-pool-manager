import Foundation

struct PoolDashboardActionFlowCoordinator {
    struct ResetAllUsageOutput {
        let state: AccountPoolState
        let resetAllLatch: DestructiveActionLatch
        let didReset: Bool
    }

    private let actionCoordinator = PoolDashboardActionCoordinator()

    func addAccount(
        to state: AccountPoolState,
        name: String,
        quota: Int
    ) -> AccountPoolState {
        var nextState = state
        actionCoordinator.addAccount(state: &nextState, name: name, quota: quota)
        return nextState
    }

    func removeAccount(
        from state: AccountPoolState,
        accountID: UUID
    ) -> AccountPoolState {
        var nextState = state
        actionCoordinator.removeAccount(state: &nextState, accountID: accountID)
        return nextState
    }

    func triggerResetAllUsage(
        from state: AccountPoolState,
        resetAllLatch: DestructiveActionLatch
    ) -> ResetAllUsageOutput {
        var nextState = state
        var nextLatch = resetAllLatch
        let shouldReset = nextLatch.confirmOrArm()
        if shouldReset {
            actionCoordinator.resetAllUsage(state: &nextState)
        }
        return ResetAllUsageOutput(
            state: nextState,
            resetAllLatch: nextLatch,
            didReset: shouldReset
        )
    }

    func simulateUsage(
        on state: AccountPoolState,
        units: Int = 50
    ) -> AccountPoolState {
        var nextState = state
        actionCoordinator.simulateUsage(state: &nextState, units: units)
        return nextState
    }

    func evaluateSwitch(on state: AccountPoolState) -> AccountPoolState {
        var nextState = state
        actionCoordinator.evaluateSwitch(state: &nextState)
        return nextState
    }

    func clearActivities(on state: AccountPoolState) -> AccountPoolState {
        var nextState = state
        actionCoordinator.clearActivities(state: &nextState)
        return nextState
    }
}
