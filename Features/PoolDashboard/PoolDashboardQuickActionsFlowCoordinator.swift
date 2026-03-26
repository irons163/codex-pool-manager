import Foundation

struct PoolDashboardQuickActionsFlowCoordinator {
    struct ResetAllUsageOutput {
        let state: AccountPoolState
        let resetAllLatch: DestructiveActionLatch
        let didReset: Bool
    }

    enum Action {
        case removeAccount(UUID)
        case simulateUsage(Int)
        case evaluateSwitch
        case clearActivities
    }

    private let actionFlowCoordinator = PoolDashboardActionFlowCoordinator()

    func apply(_ action: Action, to state: AccountPoolState) -> AccountPoolState {
        switch action {
        case let .removeAccount(accountID):
            return actionFlowCoordinator.removeAccount(from: state, accountID: accountID)
        case let .simulateUsage(units):
            return actionFlowCoordinator.simulateUsage(on: state, units: units)
        case .evaluateSwitch:
            return actionFlowCoordinator.evaluateSwitch(on: state)
        case .clearActivities:
            return actionFlowCoordinator.clearActivities(on: state)
        }
    }

    func triggerResetAllUsage(
        from state: AccountPoolState,
        resetAllLatch: DestructiveActionLatch
    ) -> ResetAllUsageOutput {
        let output = actionFlowCoordinator.triggerResetAllUsage(
            from: state,
            resetAllLatch: resetAllLatch
        )
        return ResetAllUsageOutput(
            state: output.state,
            resetAllLatch: output.resetAllLatch,
            didReset: output.didReset
        )
    }
}
