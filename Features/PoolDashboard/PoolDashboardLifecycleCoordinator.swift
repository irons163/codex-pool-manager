import Foundation

struct PoolDashboardLifecycleCoordinator {
    func onAppear(
        state: inout AccountPoolState,
        lowUsageAlertPolicy: inout LowUsageAlertPolicy
    ) {
        state.evaluate()
        _ = triggerLowUsageAlertIfNeeded(
            state: state,
            lowUsageAlertPolicy: &lowUsageAlertPolicy
        )
    }

    func shouldShowLowUsageAlert(
        state: AccountPoolState,
        lowUsageAlertPolicy: inout LowUsageAlertPolicy
    ) -> Bool {
        triggerLowUsageAlertIfNeeded(
            state: state,
            lowUsageAlertPolicy: &lowUsageAlertPolicy
        )
    }

    private func triggerLowUsageAlertIfNeeded(
        state: AccountPoolState,
        lowUsageAlertPolicy: inout LowUsageAlertPolicy
    ) -> Bool {
        lowUsageAlertPolicy.shouldTriggerAlert(
            mode: state.mode,
            hasLowUsageWarning: state.hasLowUsageWarning
        )
    }
}
