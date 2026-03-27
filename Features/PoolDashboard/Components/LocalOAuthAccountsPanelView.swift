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
                Text("Discover signed-in Codex sessions from local auth data and import them as managed pool accounts.")
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                PanelAdaptiveActionRowView {
                    headerActions
                }

                if accounts.isEmpty {
                    PanelStatusCalloutView(
                        message: "No local OAuth session was found. If Codex is signed in, choose ~/.codex/auth.json manually.",
                        title: "No Session Detected",
                        tone: .info
                    )
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
                PanelStatusCalloutView(
                    message: errorMessage,
                    title: "Scan Failed",
                    tone: .danger
                )
                .frame(maxWidth: PoolDashboardTheme.localBadgeMaxWidth, alignment: .leading)
            } else {
                Text("\(accounts.count) session(s) found")
                    .statusBadge(tone: PoolDashboardTheme.panelMutedFill)
            }
        }
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
                    PanelStatusCalloutView(
                        message: "This account has no ChatGPT account id, so usage sync is unavailable.",
                        title: "Missing Account ID",
                        tone: .warning
                    )
                }
            }

            Spacer()

            Button("Import") {
                Task { await onImport(account) }
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
