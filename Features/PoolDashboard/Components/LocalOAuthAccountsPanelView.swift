import SwiftUI

struct LocalOAuthAccountsPanelView: View {
    let accounts: [LocalCodexOAuthAccount]
    let errorMessage: String?
    let onScan: () -> Void
    let onChooseAuthFile: () -> Void
    let onImport: (LocalCodexOAuthAccount) async -> Void

    var body: some View {
        GroupBox("本機已登入 OAuth 帳號") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("掃描本機登入") {
                        onScan()
                    }
                    .buttonStyle(.bordered)

                    Button("選擇 auth.json") {
                        onChooseAuthFile()
                    }
                    .buttonStyle(.bordered)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else {
                        Text("找到 \(accounts.count) 個帳號")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if accounts.isEmpty {
                    Text("尚未找到本機 OAuth 帳號。若你已登入 Codex，請點「選擇 auth.json」並選擇 ~/.codex/auth.json")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}
