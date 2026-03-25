import Foundation

struct PoolDashboardAlertPresenter {
    func lowUsageAlertMessage(activeAccount: AgentAccount?, thresholdRatio: Double) -> String {
        if let activeAccount {
            return "\(activeAccount.name) 剩餘 \(activeAccount.remainingUnits)，已低於 \(Int(thresholdRatio * 100))% 門檻。"
        }
        return "目前帳號剩餘用量偏低。"
    }
}
