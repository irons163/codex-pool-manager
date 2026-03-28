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
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PoolDashboardTheme.panelMutedFill.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(tone.opacity(0.45), lineWidth: 0.9)
                )
        )
    }
}
