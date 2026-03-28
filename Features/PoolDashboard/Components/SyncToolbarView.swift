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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var toolbarRow: some View {
        HStack(alignment: .center, spacing: Layout.spacing) {
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
