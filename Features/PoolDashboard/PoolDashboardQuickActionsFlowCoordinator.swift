import Foundation

struct PoolDashboardQuickActionsFlowCoordinator {
    typealias ResetAllUsageOutput = PoolDashboardActionFlowCoordinator.ResetAllUsageOutput

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
        actionFlowCoordinator.triggerResetAllUsage(
            from: state,
            resetAllLatch: resetAllLatch
        )
    }
}
