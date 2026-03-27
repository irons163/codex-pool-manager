import Foundation

struct PoolDashboardAlertPresenter {
    private enum Message {
        static let genericLowUsage = "目前帳號剩餘用量偏低。"
    }

    func lowUsageAlertMessage(activeAccount: AgentAccount?, thresholdRatio: Double) -> String {
        if let activeAccount {
            return "\(activeAccount.name) 剩餘 \(activeAccount.remainingUnits)，已低於 \(Int(thresholdRatio * 100))% 門檻。"
        }
        return Message.genericLowUsage
    }
}
