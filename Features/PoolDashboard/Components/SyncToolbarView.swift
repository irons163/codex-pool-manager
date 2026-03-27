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
            VStack(alignment: .leading, spacing: 10) {
                toolbarRow
            }
        }
        .padding(PoolDashboardTheme.toolbarPadding)
        .background(
            RoundedRectangle(cornerRadius: PoolDashboardTheme.tileCornerRadius, style: .continuous)
                .fill(PoolDashboardTheme.panelStrongFill)
                .overlay(
                    RoundedRectangle(cornerRadius: PoolDashboardTheme.tileCornerRadius, style: .continuous)
                        .stroke(PoolDashboardTheme.panelStroke, lineWidth: 1)
                )
        )
        .shadow(
            color: .black.opacity(0.22),
            radius: PoolDashboardTheme.toolbarShadowRadius,
            x: 0,
            y: PoolDashboardTheme.cardShadowYOffset
        )
    }

    private var toolbarRow: some View {
        HStack(alignment: .center, spacing: Layout.spacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Usage Sync")
                    .font(PoolDashboardTheme.metadataFont.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textMuted)
                Text(isSyncing ? "Sync in progress" : "Manual refresh available")
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textSecondary)
            }

            Button(isSyncing ? "Syncing..." : "Sync Codex Usage") {
                onSync()
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .disabled(isSyncing)
            .accessibilityIdentifier("sync.toolbar.syncButton")

            if let lastSyncAt {
                PanelStatusCalloutView(
                    message: lastSyncAt.formatted(date: .omitted, time: .standard),
                    title: "Last Successful Sync",
                    tone: .info
                )
                .frame(maxWidth: PoolDashboardTheme.syncBadgeMaxWidth, alignment: .leading)
            }

            if let errorText {
                PanelStatusCalloutView(
                    message: errorText,
                    title: "Sync Error",
                    tone: .danger
                )
                .frame(maxWidth: PoolDashboardTheme.syncBadgeMaxWidth, alignment: .leading)
            }
        }
    }
}
