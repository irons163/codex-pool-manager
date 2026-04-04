import SwiftUI

struct PoolAccountUsagePresenter {
    func usageSourceLabel(for account: AgentAccount) -> String {
        if account.chatGPTAccountID != nil, account.quota == 100 {
            return L10n.text("usage.source.percent")
        }
        if account.chatGPTAccountID != nil {
            return L10n.text("usage.source.units")
        }
        return L10n.text("usage.source.manual")
    }

    func isPercentUsageAccount(_ account: AgentAccount) -> Bool {
        account.chatGPTAccountID != nil && account.quota == 100
    }

    func remainingLabel(for account: AgentAccount) -> String {
        if isPercentUsageAccount(account) {
            return L10n.text("usage.remaining_percent_format", account.remainingUnits)
        }
        return L10n.text("usage.remaining_units_format", account.remainingUnits)
    }

    func usageWindowDetailLabel(for account: AgentAccount) -> String? {
        guard account.chatGPTAccountID != nil else { return nil }

        var segments: [String] = []
        if let usageWindowName = account.usageWindowName, !usageWindowName.isEmpty {
            segments.append(L10n.text("usage.window_format", usageWindowName))
        }
        if let resetAt = account.usageWindowResetAt {
            segments.append(
                L10n.text(
                    "usage.resets_format",
                    resetAt.formatted(.dateTime.locale(L10n.locale()).month().day().hour().minute())
                )
            )
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
