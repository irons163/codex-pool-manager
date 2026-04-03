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
        if account.isPaid, let primaryUsagePercent = account.primaryUsagePercent {
            return max(0, min(100, 100 - primaryUsagePercent))
        }
        return max(0, min(100, Int((account.remainingRatio * 100).rounded())))
    }
}
