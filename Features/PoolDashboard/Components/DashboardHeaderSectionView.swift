import SwiftUI

struct DashboardHeaderSectionView: View {
    let accountCount: Int
    let availableCount: Int
    let overallUsagePercent: Int
    let modeTitle: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(tiles) { tile in
                    dashboardTile(tile)
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(tiles) { tile in
                    dashboardTile(tile)
                }
            }
        }
    }

    private var tiles: [DashboardHeaderTile] {
        [
            DashboardHeaderTile(title: L10n.text("header.accounts"), value: "\(accountCount)", tone: .blue),
            DashboardHeaderTile(title: L10n.text("header.available"), value: "\(availableCount)", tone: .green),
            DashboardHeaderTile(title: L10n.text("header.pool_usage"), value: "\(overallUsagePercent)%", tone: .orange),
            DashboardHeaderTile(title: L10n.text("header.mode"), value: localizedModeTitle(modeTitle), tone: .indigo)
        ]
    }

    private func localizedModeTitle(_ title: String) -> String {
        switch title {
        case "智能切換", "Intelligent", "intelligent":
            return L10n.text("mode.intelligent")
        case "手動切換", "Manual", "manual":
            return L10n.text("mode.manual")
        case "專注模式", "Focus", "focus":
            return L10n.text("mode.focus")
        default:
            return title
        }
    }

    private func dashboardTile(_ tile: DashboardHeaderTile) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(tile.title.uppercased())
                .font(PoolDashboardTheme.metadataFont.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(PoolDashboardTheme.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(tile.value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PoolDashboardTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, PoolDashboardTheme.headerTileVerticalPadding)
        .padding(.horizontal, PoolDashboardTheme.headerTileHorizontalPadding)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PoolDashboardTheme.panelMutedFill.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(tile.tone.opacity(0.45), lineWidth: 0.9)
                )
        )
    }
}

private struct DashboardHeaderTile: Identifiable {
    var id: String { title }
    let title: String
    let value: String
    let tone: Color
}
