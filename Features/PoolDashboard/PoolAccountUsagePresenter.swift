import SwiftUI

struct PoolAccountUsagePresenter {
    func usageSourceLabel(for account: AgentAccount) -> String {
        if account.chatGPTAccountID != nil, account.quota == 100 {
            return "Source: response.rate_limit.primary_window.used_percent"
        }
        if account.chatGPTAccountID != nil {
            return "Source: response.used_units / quota"
        }
        return "Source: manual/local override"
    }

    func isPercentUsageAccount(_ account: AgentAccount) -> Bool {
        account.chatGPTAccountID != nil && account.quota == 100
    }

    func remainingLabel(for account: AgentAccount) -> String {
        if isPercentUsageAccount(account) {
            return "Remaining \(account.remainingUnits)%"
        }
        return "Remaining \(account.remainingUnits)"
    }

    func usageWindowDetailLabel(for account: AgentAccount) -> String? {
        guard account.chatGPTAccountID != nil else { return nil }

        var segments: [String] = []
        if let usageWindowName = account.usageWindowName, !usageWindowName.isEmpty {
            segments.append("Window: \(usageWindowName)")
        }
        if let resetAt = account.usageWindowResetAt {
            segments.append("Resets: \(resetAt.formatted(.dateTime.month().day().hour().minute()))")
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
