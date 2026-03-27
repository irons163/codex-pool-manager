import SwiftUI

struct SyncToolbarView: View {
    let isSyncing: Bool
    let lastSyncAt: Date?
    let errorText: String?
    let onSync: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(isSyncing ? "同步中..." : "同步 Codex 用量") {
                onSync()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSyncing)
            .tint(PoolDashboardTheme.glowA)

            if let lastSyncAt {
                badge(
                    "最近同步：\(lastSyncAt.formatted(date: .omitted, time: .standard))",
                    tone: .white.opacity(0.18)
                )
            }

            if let errorText {
                badge(errorText, tone: .red.opacity(0.35))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: PoolDashboardTheme.tileCornerRadius, style: .continuous)
                .fill(PoolDashboardTheme.panelFill.opacity(0.70))
        )
    }

    private func badge(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.86))
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(tone)
            )
    }
}
