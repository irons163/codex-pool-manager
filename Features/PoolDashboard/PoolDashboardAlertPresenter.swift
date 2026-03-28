import Foundation

struct PoolDashboardAlertPresenter {
    func lowUsageAlertMessage(activeAccount: AgentAccount?, thresholdRatio: Double) -> String {
        if let activeAccount {
            return L10n.text(
                "alert.low_usage.message.account_format",
                activeAccount.name,
                activeAccount.remainingUnits,
                Int(thresholdRatio * 100)
            )
        }
        return L10n.text("alert.low_usage.message.generic")
    }
}
