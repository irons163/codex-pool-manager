import SwiftUI

struct OverallUsagePanelView: View {
    let totalUsedUnits: Int
    let totalQuota: Int
    let overallUsageRatio: Double
    let availableAccountsCount: Int
    let isPoolExhausted: Bool
    let resetAllButtonTitle: String
    let onResetAll: () -> Void

    var body: some View {
        GroupBox("整體用量") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("總用量 \(totalUsedUnits)/\(totalQuota)")
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                    Spacer()
                    Text("\(Int(overallUsageRatio * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                }

                ProgressView(value: overallUsageRatio)
                    .tint(PoolDashboardTheme.glowA)

                Button(resetAllButtonTitle) {
                    onResetAll()
                }
                .buttonStyle(DashboardWarningButtonStyle())

                HStack {
                    Text("可用帳號數 \(availableAccountsCount)")
                        .font(.subheadline)
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                    Spacer()
                }

                if isPoolExhausted {
                    Text("所有帳號用量已耗盡，請補充配額或重設用量。")
                        .font(.subheadline)
                        .foregroundStyle(PoolDashboardTheme.danger)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(PoolDashboardTheme.danger.opacity(0.18))
                        )
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }
}
