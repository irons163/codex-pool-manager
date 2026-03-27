import SwiftUI

struct AccountUsagePanelView: View {
    @Binding var newAccountName: String
    @Binding var newAccountQuota: Int

    let accounts: [AgentAccount]
    let onAddAccount: (String, Int) -> Void
    let onSwitchAndLaunch: (AgentAccount) async -> Void
    let onRemoveAccount: (UUID) -> Void

    let accountNameBinding: (UUID) -> Binding<String>
    let accountQuotaBinding: (UUID) -> Binding<Int>
    let accountUsedBinding: (UUID) -> Binding<Int>

    let usageSourceLabel: (AgentAccount) -> String
    let usageWindowDetailLabel: (AgentAccount) -> String?
    let isPercentUsageAccount: (AgentAccount) -> Bool
    let remainingLabel: (AgentAccount) -> String
    let usageProgressColor: (AgentAccount) -> Color

    var body: some View {
        GroupBox("帳號用量") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    TextField("新帳號名稱", text: $newAccountName)
                        .textFieldStyle(.roundedBorder)
                    Stepper("配額 \(newAccountQuota)", value: $newAccountQuota, in: 100...10_000, step: 100)
                    Button("新增帳號") {
                        onAddAccount(newAccountName.trimmingCharacters(in: .whitespacesAndNewlines), newAccountQuota)
                        newAccountName = ""
                    }
                    .buttonStyle(DashboardPrimaryButtonStyle())
                }

                List {
                    ForEach(accounts) { account in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    TextField("帳號名稱", text: accountNameBinding(account.id))
                                        .textFieldStyle(.roundedBorder)
                                    if let chatGPTAccountID = account.chatGPTAccountID {
                                        Text("Account ID: \(chatGPTAccountID)")
                                            .font(.caption)
                                            .foregroundStyle(PoolDashboardTheme.textMuted)
                                    }
                                    Text(usageSourceLabel(account))
                                        .font(.caption)
                                        .foregroundStyle(PoolDashboardTheme.textMuted)
                                    if let usageWindowDetail = usageWindowDetailLabel(account) {
                                        Text(usageWindowDetail)
                                            .font(.caption)
                                            .foregroundStyle(PoolDashboardTheme.textMuted)
                                    }
                                }
                                Spacer()
                                Button("切換並啟動") {
                                    Task {
                                        await onSwitchAndLaunch(account)
                                    }
                                }
                                .buttonStyle(DashboardPrimaryButtonStyle())
                                Button("刪除", role: .destructive) {
                                    onRemoveAccount(account.id)
                                }
                                .buttonStyle(DashboardSubtleButtonStyle())
                            }

                            if isPercentUsageAccount(account) {
                                HStack {
                                    Text("已用 \(account.usedUnits)%")
                                    Spacer()
                                    Text("剩餘 \(account.remainingUnits)%")
                                }
                                .font(.subheadline)
                            } else {
                                HStack {
                                    Stepper(
                                        "已用 \(account.usedUnits)",
                                        value: accountUsedBinding(account.id),
                                        in: 0...account.quota,
                                        step: 50
                                    )
                                    Stepper(
                                        "配額 \(account.quota)",
                                        value: accountQuotaBinding(account.id),
                                        in: 100...20_000,
                                        step: 100
                                    )
                                }
                            }

                            HStack {
                                Text(remainingLabel(account))
                                    .font(.caption)
                                    .foregroundStyle(PoolDashboardTheme.textMuted)
                                Spacer()
                                Text("\(Int(account.usageRatio * 100))%")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(PoolDashboardTheme.textMuted)
                            }

                            ProgressView(value: account.usageRatio)
                                .tint(usageProgressColor(account))
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(PoolDashboardTheme.panelMutedFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: 1)
                                )
                                .padding(.vertical, 2)
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 240)
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }
}
