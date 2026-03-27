import SwiftUI

struct LocalOAuthAccountsPanelView: View {
    let accounts: [LocalCodexOAuthAccount]
    let errorMessage: String?
    let onScan: () -> Void
    let onChooseAuthFile: () -> Void
    let onImport: (LocalCodexOAuthAccount) async -> Void

    var body: some View {
        GroupBox("本機已登入 OAuth 帳號") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("掃描本機登入") {
                        onScan()
                    }
                    .buttonStyle(.bordered)
                    .tint(PoolDashboardTheme.glowA)

                    Button("選擇 auth.json") {
                        onChooseAuthFile()
                    }
                    .buttonStyle(.bordered)
                    .tint(PoolDashboardTheme.glowB)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.red.opacity(0.16))
                            )
                    } else {
                        Text("找到 \(accounts.count) 個帳號")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.70))
                    }
                }

                if accounts.isEmpty {
                    Text("尚未找到本機 OAuth 帳號。若你已登入 Codex，請點「選擇 auth.json」並選擇 ~/.codex/auth.json")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.70))
                } else {
                    ForEach(accounts) { account in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.displayName)
                                if let email = account.email {
                                    Text(email)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Text(account.maskedToken)
                                    .font(.footnote)
                                    .monospaced()
                                    .foregroundStyle(.secondary)
                                if let chatGPTAccountID = account.chatGPTAccountID {
                                    Text("Account ID: \(chatGPTAccountID)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("缺少 Account ID，無法查詢用量")
                                        .font(.footnote)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Button("匯入") {
                                Task {
                                    await onImport(account)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(account.chatGPTAccountID == nil)
                            .tint(PoolDashboardTheme.glowA)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(PoolDashboardTheme.panelFill.opacity(0.62))
                        )
                    }
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }
}
