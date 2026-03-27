import SwiftUI

struct LocalOAuthAccountsPanelView: View {
    let accounts: [LocalCodexOAuthAccount]
    let errorMessage: String?
    let onScan: () -> Void
    let onChooseAuthFile: () -> Void
    let onImport: (LocalCodexOAuthAccount) async -> Void

    var body: some View {
        GroupBox("Local OAuth Sessions") {
            VStack(alignment: .leading, spacing: PoolDashboardTheme.localOAuthPanelSpacing) {
                Text("Discover signed-in Codex sessions from your local auth file and import them as managed accounts.")
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                ViewThatFits(in: .horizontal) {
                    headerActions
                    VStack(alignment: .leading, spacing: PoolDashboardTheme.actionRowSpacing) {
                        headerActions
                    }
                }

                if accounts.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(accounts) { account in
                            accountRow(account)
                        }
                    }
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }

    private var headerActions: some View {
        HStack(spacing: PoolDashboardTheme.actionRowSpacing) {
            Button("Scan Local Sessions") {
                onScan()
            }
            .buttonStyle(DashboardSubtleButtonStyle())

            Button("Choose auth.json") {
                onChooseAuthFile()
            }
            .buttonStyle(DashboardSubtleButtonStyle())

            if let errorMessage {
                Text(errorMessage)
                    .lineLimit(1)
                    .frame(maxWidth: PoolDashboardTheme.localBadgeMaxWidth, alignment: .leading)
                    .statusBadge(tone: PoolDashboardTheme.danger.opacity(0.24))
            } else {
                Text("\(accounts.count) session(s) found")
                    .statusBadge(tone: PoolDashboardTheme.panelMutedFill)
            }
        }
    }

    private var emptyState: some View {
        Text("No local OAuth session was found. If Codex is signed in, choose `~/.codex/auth.json` manually.")
            .font(.footnote)
            .foregroundStyle(PoolDashboardTheme.textSecondary)
            .calloutCard(fill: PoolDashboardTheme.panelMutedFill, border: PoolDashboardTheme.panelInnerStroke)
    }

    private func accountRow(_ account: LocalCodexOAuthAccount) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(account.displayName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(PoolDashboardTheme.textPrimary)

                if let email = account.email {
                    Text(email)
                        .font(.footnote)
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                }

                Text(account.maskedToken)
                    .font(.footnote)
                    .monospaced()
                    .foregroundStyle(PoolDashboardTheme.textMuted)
                    .lineLimit(1)

                if let chatGPTAccountID = account.chatGPTAccountID {
                    Text("Account ID: \(chatGPTAccountID)")
                        .font(.footnote)
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                } else {
                    Text("Missing Account ID: usage sync unavailable")
                        .font(.footnote)
                        .foregroundStyle(PoolDashboardTheme.warning)
                }
            }

            Spacer()

            Button("Import") {
                Task {
                    await onImport(account)
                }
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .disabled(account.chatGPTAccountID == nil)
        }
        .padding(.vertical, PoolDashboardTheme.listRowVerticalInset * 3)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: PoolDashboardTheme.editorCornerRadius, style: .continuous)
                .fill(PoolDashboardTheme.panelMutedFill)
                .overlay(
                    RoundedRectangle(cornerRadius: PoolDashboardTheme.editorCornerRadius, style: .continuous)
                        .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: 1)
                )
        )
    }
}
