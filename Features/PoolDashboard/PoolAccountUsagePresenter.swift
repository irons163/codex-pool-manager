import SwiftUI

struct PoolAccountUsagePresenter {
    func usageSourceLabel(for account: AgentAccount) -> String {
        if account.chatGPTAccountID != nil, account.quota == 100 {
            return "用量來源：response.rate_limit.primary_window.used_percent"
        }
        if account.chatGPTAccountID != nil {
            return "用量來源：response.used_units / quota"
        }
        return "用量來源：手動/本地設定"
    }

    func isPercentUsageAccount(_ account: AgentAccount) -> Bool {
        account.chatGPTAccountID != nil && account.quota == 100
    }

    func remainingLabel(for account: AgentAccount) -> String {
        if isPercentUsageAccount(account) {
            return "剩餘 \(account.remainingUnits)%"
        }
        return "剩餘 \(account.remainingUnits)"
    }

    func usageWindowDetailLabel(for account: AgentAccount) -> String? {
        guard account.chatGPTAccountID != nil else { return nil }

        var segments: [String] = []
        if let usageWindowName = account.usageWindowName, !usageWindowName.isEmpty {
            segments.append("視窗：\(usageWindowName)")
        }
        if let resetAt = account.usageWindowResetAt {
            segments.append("重置：\(resetAt.formatted(.dateTime.month().day().hour().minute()))")
        }
        return segments.isEmpty ? nil : segments.joined(separator: " · ")
    }

    func usageProgressColor(for account: AgentAccount) -> Color {
        let ratio = account.usageRatio
        if ratio >= 0.9 { return .red }
        if ratio >= 0.7 { return .orange }
        return .blue
    }
}
