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
        GroupBox("Pool Overview") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Monitor aggregate capacity and reset usage during controlled maintenance windows.")
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                HStack {
                    Text("Total usage \(totalUsedUnits)/\(totalQuota)")
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                    Spacer()
                    Text("\(Int(overallUsageRatio * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                }

                ProgressView(value: overallUsageRatio)
                    .tint(PoolDashboardTheme.glowA)
                    .scaleEffect(x: 1, y: 1.25, anchor: .center)

                Button(resetAllButtonTitle) {
                    onResetAll()
                }
                .buttonStyle(DashboardWarningButtonStyle())

                Text("Available accounts: \(availableAccountsCount)")
                    .statusBadge(tone: PoolDashboardTheme.panelMutedFill)

                if isPoolExhausted {
                    Text("All accounts are exhausted. Increase quota or reset usage to resume switching.")
                        .font(.subheadline)
                        .foregroundStyle(PoolDashboardTheme.danger)
                        .calloutCard(fill: PoolDashboardTheme.danger.opacity(0.18))
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }
}
