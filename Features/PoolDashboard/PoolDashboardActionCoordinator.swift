import Foundation

struct PoolDashboardActionCoordinator {
    func addAccount(state: inout AccountPoolState, name: String, quota: Int) {
        state.addAccount(name: name, quota: quota)
    }

    func removeAccount(state: inout AccountPoolState, accountID: UUID) {
        state.removeAccount(accountID)
    }

    func resetAllUsage(state: inout AccountPoolState) {
        state.resetAllUsage()
    }

    func simulateUsage(state: inout AccountPoolState, units: Int = 50) {
        state.recordUsage(units: units)
    }

    func evaluateSwitch(state: inout AccountPoolState) {
        state.evaluate()
    }

    func clearActivities(state: inout AccountPoolState) {
        state.clearActivities()
    }
}
