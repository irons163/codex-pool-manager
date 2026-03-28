import SwiftUI

struct AccountUsagePanelView: View {
    @Binding var newAccountName: String
    @Binding var newAccountQuota: Int

    let accounts: [AgentAccount]
    let showAddAccountControls: Bool
    let onAddAccount: (String, Int) -> Void
    let onSwitchAndLaunch: (AgentAccount) async -> Void
    let onRemoveAccount: (UUID) -> Void

    let accountNameBinding: (UUID) -> Binding<String>
    let accountQuotaBinding: (UUID) -> Binding<Int>
    let accountUsedBinding: (UUID) -> Binding<Int>

    let isPercentUsageAccount: (AgentAccount) -> Bool
    let remainingLabel: (AgentAccount) -> String
    let usageProgressColor: (AgentAccount) -> Color

    var body: some View {
        GroupBox("Account Usage") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Manage quotas, trigger switches, and monitor utilization per account.")
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                if showAddAccountControls {
                    PanelAdaptiveActionRowView {
                        addRow
                    }
                }

                PanelStatusCalloutView(
                    message: "\(accounts.count) account(s) are currently managed in the pool.",
                    title: "Managed Accounts",
                    tone: .info
                )

                List {
                    ForEach(accounts) { account in
                        VStack(alignment: .leading, spacing: 8) {
                            ViewThatFits(in: .horizontal) {
                                accountIdentityRow(account)
                                VStack(alignment: .leading, spacing: 8) {
                                    accountIdentityRow(account)
                                }
                            }

                            if isPercentUsageAccount(account) {
                                HStack {
                                    Text("Used \(account.usedUnits)%")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("Remaining \(account.remainingUnits)%")
                                        .font(.subheadline)
                                }
                            } else {
                                HStack {
                                    Stepper(
                                        "Used \(account.usedUnits)",
                                        value: accountUsedBinding(account.id),
                                        in: 0...account.quota,
                                        step: 50
                                    )
                                    Stepper(
                                        "Quota \(account.quota)",
                                        value: accountQuotaBinding(account.id),
                                        in: 100...20_000,
                                        step: 100
                                    )
                                }
                            }

                            ProgressView(value: account.usageRatio)
                                .tint(usageProgressColor(account))
                        }
                        .padding(.vertical, 4)
                        .dashboardListRowCard()
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(minHeight: PoolDashboardTheme.usageListMinHeight)
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }

    private var addRow: some View {
        HStack(spacing: PoolDashboardTheme.accountAddRowSpacing) {
            TextField("New account name", text: $newAccountName)
                .dashboardInputFieldStyle()

            Stepper("Quota \(newAccountQuota)", value: $newAccountQuota, in: 100...10_000, step: 100)
                .monospacedDigit()

            Button("Add Account") {
                onAddAccount(newAccountName.trimmingCharacters(in: .whitespacesAndNewlines), newAccountQuota)
                newAccountName = ""
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .accessibilityIdentifier("usage.addAccountButton")
        }
    }

    private func accountIdentityRow(_ account: AgentAccount) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Account name", text: accountNameBinding(account.id))
                    .dashboardInputFieldStyle()

            }

            Spacer()

            HStack(spacing: 8) {
                Button("Switch & Launch") {
                    Task {
                        await onSwitchAndLaunch(account)
                    }
                }
                .buttonStyle(DashboardPrimaryButtonStyle())

                Button("Delete", role: .destructive) {
                    onRemoveAccount(account.id)
                }
                .buttonStyle(DashboardWarningButtonStyle())
            }
        }
    }
}
