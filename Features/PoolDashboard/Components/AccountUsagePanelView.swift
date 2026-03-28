import SwiftUI

struct AccountUsagePanelView: View {
    private enum LayoutMode: String, CaseIterable, Identifiable {
        case single = "單排"
        case double = "雙排"
        case triple = "三排"

        var id: String { rawValue }

        var columns: Int {
            switch self {
            case .single: 1
            case .double: 2
            case .triple: 3
            }
        }
    }

    @State private var layoutMode: LayoutMode = .single

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

                Picker("排列", selection: $layoutMode) {
                    ForEach(LayoutMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                ScrollView {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
                        ForEach(accounts) { account in
                            accountCard(account)
                        }
                    }
                }
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

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 220), spacing: 10), count: layoutMode.columns)
    }

    private func accountCard(_ account: AgentAccount) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            accountNameRow(account)
            accountActionRow(account)

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

    private func accountNameRow(_ account: AgentAccount) -> some View {
        TextField("Account name", text: accountNameBinding(account.id))
            .dashboardInputFieldStyle()
    }

    private func accountActionRow(_ account: AgentAccount) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            Button("Switch & Launch") {
                Task {
                    await onSwitchAndLaunch(account)
                }
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .lineLimit(1)
            .minimumScaleFactor(0.85)

            Button("Delete", role: .destructive) {
                onRemoveAccount(account.id)
            }
            .buttonStyle(DashboardWarningButtonStyle())
            .lineLimit(1)
            .minimumScaleFactor(0.9)
        }
    }
}
