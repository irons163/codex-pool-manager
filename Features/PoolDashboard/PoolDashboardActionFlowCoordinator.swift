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
        mutate(state) { nextState in
            actionCoordinator.addAccount(state: &nextState, name: name, quota: quota)
        }
    }

    func removeAccount(
        from state: AccountPoolState,
        accountID: UUID
    ) -> AccountPoolState {
        mutate(state) { nextState in
            actionCoordinator.removeAccount(state: &nextState, accountID: accountID)
        }
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
        mutate(state) { nextState in
            actionCoordinator.simulateUsage(state: &nextState, units: units)
        }
    }

    func evaluateSwitch(on state: AccountPoolState) -> AccountPoolState {
        mutate(state) { nextState in
            actionCoordinator.evaluateSwitch(state: &nextState)
        }
    }

    func clearActivities(on state: AccountPoolState) -> AccountPoolState {
        mutate(state) { nextState in
            actionCoordinator.clearActivities(state: &nextState)
        }
    }

    private func mutate(
        _ state: AccountPoolState,
        apply: (inout AccountPoolState) -> Void
    ) -> AccountPoolState {
        var nextState = state
        apply(&nextState)
        return nextState
    }

}
