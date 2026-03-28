import SwiftUI

struct DashboardHeaderSectionView: View {
    let accountCount: Int
    let availableCount: Int
    let overallUsagePercent: Int
    let modeTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                dashboardTile(title: "Accounts", value: "\(accountCount)", tone: .blue)
                dashboardTile(title: "Available", value: "\(availableCount)", tone: .green)
                dashboardTile(title: "Pool Usage", value: "\(overallUsagePercent)%", tone: .orange)
                dashboardTile(title: "Mode", value: modeTitle, tone: .indigo)
            }
            .layoutPriority(0)
        }
    }

    private func dashboardTile(title: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(PoolDashboardTheme.metadataFont.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(PoolDashboardTheme.textMuted)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PoolDashboardTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, PoolDashboardTheme.headerTileVerticalPadding)
        .padding(.horizontal, PoolDashboardTheme.headerTileHorizontalPadding)
        .background(
            RoundedRectangle(cornerRadius: PoolDashboardTheme.tileCornerRadius, style: .continuous)
                .fill(PoolDashboardTheme.panelStrongFill)
                .overlay(
                    RoundedRectangle(cornerRadius: PoolDashboardTheme.tileCornerRadius, style: .continuous)
                        .stroke(tone.opacity(0.55), lineWidth: PoolDashboardTheme.tileBorderWidth)
                )
        )
        .shadow(
            color: tone.opacity(0.18),
            radius: PoolDashboardTheme.tileShadowRadius,
            x: 0,
            y: PoolDashboardTheme.cardShadowYOffset
        )
    }
}
