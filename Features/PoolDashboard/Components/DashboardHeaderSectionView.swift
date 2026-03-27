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
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.62))
                Text("Codex Account Orchestrator")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("管理 OAuth 帳號、監控用量、快速切換執行環境")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
            }

            HStack(spacing: 12) {
                dashboardTile(title: "帳號", value: "\(accountCount)", tone: .blue)
                dashboardTile(title: "可用", value: "\(availableCount)", tone: .green)
                dashboardTile(title: "總用量", value: "\(overallUsagePercent)%", tone: .orange)
                dashboardTile(title: "模式", value: modeTitle, tone: .indigo)
            }
        }
    }

    private func dashboardTile(title: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.68))
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: PoolDashboardTheme.tileCornerRadius, style: .continuous)
                .fill(PoolDashboardTheme.panelFill.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: PoolDashboardTheme.tileCornerRadius, style: .continuous)
                        .stroke(tone.opacity(0.55), lineWidth: 1)
                )
        )
    }
}
