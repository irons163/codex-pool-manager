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
        GroupBox(L10n.text("overview.title")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("overview.subtitle"))
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                HStack {
                    Text(L10n.text("overview.total_usage_format", totalUsedUnits, totalQuota))
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                    Spacer()
                    Text("\(Int(overallUsageRatio * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                }
                .dashboardInfoCard()

                ProgressView(value: overallUsageRatio)
                    .tint(PoolDashboardTheme.glowA)
                    .scaleEffect(x: 1, y: 1.25, anchor: .center)

                Button(resetAllButtonTitle) {
                    onResetAll()
                }
                .buttonStyle(DashboardWarningButtonStyle())

                Text(L10n.text("overview.available_accounts_format", availableAccountsCount))
                    .statusBadge(tone: PoolDashboardTheme.panelMutedFill)

                if isPoolExhausted {
                    PanelStatusCalloutView(
                        message: L10n.text("overview.pool_exhausted.message"),
                        title: L10n.text("overview.pool_exhausted.title"),
                        tone: .danger
                    )
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }
}
