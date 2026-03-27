import SwiftUI

struct DashboardHeaderSectionView: View {
    let accountCount: Int
    let availableCount: Int
    let overallUsagePercent: Int
    let modeTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("AIAGENTPOOL CONTROL CENTER")
                    .font(PoolDashboardTheme.metadataFont.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(PoolDashboardTheme.textMuted)
                Text("Codex Account Orchestrator")
                    .font(PoolDashboardTheme.titleFont)
                    .foregroundStyle(PoolDashboardTheme.textPrimary)
                Text("管理 OAuth 帳號、監控用量、快速切換執行環境")
                    .font(PoolDashboardTheme.subtitleFont)
                    .foregroundStyle(PoolDashboardTheme.textSecondary)
                    .frame(maxWidth: PoolDashboardTheme.subtitleReadableWidth, alignment: .leading)
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [PoolDashboardTheme.glowA.opacity(0.75), PoolDashboardTheme.glowB.opacity(0.45)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: PoolDashboardTheme.headerAccentRuleWidth, height: 3)
            }

            HStack(spacing: 14) {
                dashboardTile(title: "帳號", value: "\(accountCount)", tone: .blue)
                dashboardTile(title: "可用", value: "\(availableCount)", tone: .green)
                dashboardTile(title: "總用量", value: "\(overallUsagePercent)%", tone: .orange)
                dashboardTile(title: "模式", value: modeTitle, tone: .indigo)
            }
            .layoutPriority(1)
        }
    }

    private func dashboardTile(title: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(PoolDashboardTheme.textMuted)
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PoolDashboardTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: PoolDashboardTheme.tileCornerRadius, style: .continuous)
                .fill(PoolDashboardTheme.panelStrongFill)
                .overlay(
                    RoundedRectangle(cornerRadius: PoolDashboardTheme.tileCornerRadius, style: .continuous)
                        .stroke(tone.opacity(0.55), lineWidth: PoolDashboardTheme.tileBorderWidth)
                )
        )
        .shadow(color: tone.opacity(0.18), radius: PoolDashboardTheme.tileShadowRadius, x: 0, y: 6)
    }
}
