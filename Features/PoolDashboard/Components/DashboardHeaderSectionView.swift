import SwiftUI

struct DashboardHeaderSectionView: View {
    let accountCount: Int
    let availableCount: Int
    let overallUsagePercent: Int
    let modeTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Codex Account Orchestrator")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("管理 OAuth 帳號、監控用量、快速切換執行環境")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
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
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(tone.opacity(0.35), lineWidth: 1)
                )
        )
    }
}
