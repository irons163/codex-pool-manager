import SwiftUI

struct SyncToolbarView: View {
    private enum Layout {
        static let spacing: CGFloat = 10
    }

    let isSyncing: Bool
    let lastSyncAt: Date?
    let errorText: String?
    let onSync: () -> Void
    let onRetry: () -> Void
    let onForceRetry: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            toolbarRow
            VStack(alignment: .leading, spacing: 8) {
                syncActions
                syncStatusBadges
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var toolbarRow: some View {
        HStack(alignment: .center, spacing: Layout.spacing) {
            Button(isSyncing ? L10n.text("sync.syncing") : L10n.text("sync.sync_codex_usage")) {
                onSync()
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .disabled(isSyncing)
            .accessibilityIdentifier("sync.toolbar.syncButton")

            if isSyncing {
                Button(L10n.text("sync.force_retry")) {
                    onForceRetry()
                }
                .buttonStyle(DashboardWarningButtonStyle())
                .accessibilityIdentifier("sync.toolbar.forceRetryButton")
            } else if let errorText, !errorText.isEmpty {
                Button(L10n.text("sync.retry")) {
                    onRetry()
                }
                .buttonStyle(DashboardWarningButtonStyle())
                .accessibilityIdentifier("sync.toolbar.retryButton")
            }

            if let lastSyncAt {
                PanelStatusCalloutView(
                    message: localizedSyncTimeText(lastSyncAt),
                    title: L10n.text("sync.last_successful_sync"),
                    tone: .info
                )
                .frame(maxWidth: PoolDashboardTheme.syncBadgeMaxWidth, alignment: .leading)
            }

            if let errorText {
                PanelStatusCalloutView(
                    message: errorText,
                    title: L10n.text("sync.error"),
                    tone: .danger
                )
                .frame(maxWidth: PoolDashboardTheme.syncBadgeMaxWidth, alignment: .leading)
            }
        }
    }

    private var syncActions: some View {
        HStack(alignment: .center, spacing: Layout.spacing) {
            Button(isSyncing ? L10n.text("sync.syncing") : L10n.text("sync.sync_codex_usage")) {
                onSync()
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .disabled(isSyncing)
            .accessibilityIdentifier("sync.toolbar.syncButton")

            if isSyncing {
                Button(L10n.text("sync.force_retry")) {
                    onForceRetry()
                }
                .buttonStyle(DashboardWarningButtonStyle())
                .accessibilityIdentifier("sync.toolbar.forceRetryButton")
            } else if let errorText, !errorText.isEmpty {
                Button(L10n.text("sync.retry")) {
                    onRetry()
                }
                .buttonStyle(DashboardWarningButtonStyle())
                .accessibilityIdentifier("sync.toolbar.retryButton")
            }
        }
    }

    @ViewBuilder
    private var syncStatusBadges: some View {
        if lastSyncAt != nil || errorText != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let lastSyncAt {
                    PanelStatusCalloutView(
                        message: localizedSyncTimeText(lastSyncAt),
                        title: L10n.text("sync.last_successful_sync"),
                        tone: .info
                    )
                    .frame(maxWidth: PoolDashboardTheme.syncBadgeMaxWidth, alignment: .leading)
                }

                if let errorText {
                    PanelStatusCalloutView(
                        message: errorText,
                        title: L10n.text("sync.error"),
                        tone: .danger
                    )
                    .frame(maxWidth: PoolDashboardTheme.syncBadgeMaxWidth, alignment: .leading)
                }
            }
        }
    }

    private func localizedSyncTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale()
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
