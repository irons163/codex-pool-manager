import SwiftUI

struct LocalOAuthAccountsPanelView: View {
    let accounts: [LocalCodexOAuthAccount]
    let errorMessage: String?
    let onScan: () -> Void
    let onChooseAuthFile: () -> Void
    let onImport: (LocalCodexOAuthAccount) async -> Void

    var body: some View {
        GroupBox("本機已登入 OAuth 帳號") {
            VStack(alignment: .leading, spacing: PoolDashboardTheme.localOAuthPanelSpacing) {
                ViewThatFits(in: .horizontal) {
                    headerActions
                    VStack(alignment: .leading, spacing: 8) {
                        headerActions
                    }
                }

                if accounts.isEmpty {
                    Text("尚未找到本機 OAuth 帳號。若你已登入 Codex，請點「選擇 auth.json」並選擇 ~/.codex/auth.json")
                        .font(.footnote)
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                } else {
                    ForEach(accounts) { account in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
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
                                    Text("缺少 Account ID，無法查詢用量")
                                        .font(.footnote)
                                        .foregroundStyle(PoolDashboardTheme.warning)
                                }
                            }
                            Spacer()
                            Button("匯入") {
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
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }

    private var headerActions: some View {
        HStack(spacing: PoolDashboardTheme.actionRowSpacing) {
            Button("掃描本機登入") {
                onScan()
            }
            .buttonStyle(DashboardSubtleButtonStyle())

            Button("選擇 auth.json") {
                onChooseAuthFile()
            }
            .buttonStyle(DashboardSubtleButtonStyle())

            if let errorMessage {
                Text(errorMessage)
                    .lineLimit(1)
                    .statusBadge(tone: PoolDashboardTheme.danger.opacity(0.24))
            } else {
                Text("找到 \(accounts.count) 個帳號")
                    .statusBadge(tone: PoolDashboardTheme.panelMutedFill)
            }
        }
    }
}
