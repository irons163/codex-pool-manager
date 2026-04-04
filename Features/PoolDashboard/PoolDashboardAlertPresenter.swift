import Foundation

struct PoolDashboardAlertPresenter {
    func lowUsageAlertMessage(activeAccount: AgentAccount?, thresholdRatio: Double) -> String {
        if let activeAccount {
            let remainingPercent = remainingPercent(for: activeAccount)
            return L10n.text(
                "alert.low_usage.message.account_format",
                activeAccount.name,
                remainingPercent,
                Int(thresholdRatio * 100)
            )
        }
        return L10n.text("alert.low_usage.message.generic")
    }

    private func remainingPercent(for account: AgentAccount) -> Int {
        account.smartSwitchRemainingPercent
    }
}
