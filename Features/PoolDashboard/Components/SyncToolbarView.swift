import SwiftUI

struct SyncToolbarView: View {
    private enum Layout {
        static let spacing: CGFloat = 10
    }

    let isSyncing: Bool
    let lastSyncAt: Date?
    let errorText: String?
    let onSync: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            toolbarRow
            VStack(alignment: .leading, spacing: 8) {
                toolbarRow
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: PoolDashboardTheme.tileCornerRadius, style: .continuous)
                .fill(PoolDashboardTheme.panelStrongFill)
                .overlay(
                    RoundedRectangle(cornerRadius: PoolDashboardTheme.tileCornerRadius, style: .continuous)
                        .stroke(PoolDashboardTheme.panelStroke, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 6)
    }

    private var toolbarRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.spacing) {
            Button(isSyncing ? "同步中..." : "同步 Codex 用量") {
                onSync()
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .disabled(isSyncing)

            if let lastSyncAt {
                badge(
                    "最近同步：\(lastSyncAt.formatted(date: .omitted, time: .standard))",
                    tone: PoolDashboardTheme.panelMutedFill,
                    useMonospacedDigits: true
                )
            }

            if let errorText {
                badge(errorText, tone: PoolDashboardTheme.danger.opacity(0.28), useMonospacedDigits: false)
            }
        }
    }

    private func badge(
        _ text: String,
        tone: Color,
        useMonospacedDigits: Bool
    ) -> some View {
        Group {
            if useMonospacedDigits {
                Text(text)
                    .font(.footnote)
                    .monospacedDigit()
            } else {
                Text(text)
                    .font(.footnote)
            }
        }
        .statusBadge(tone: tone)
    }
}
