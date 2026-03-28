import SwiftUI

struct AccountUsagePanelView: View {
    private enum SortMode: String, CaseIterable, Identifiable {
        case joinedAt = "加入時間"
        case name = "名稱"
        case remainingHigh = "剩餘用量高到低"

        var id: String { rawValue }
    }

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

    @State private var sortMode: SortMode = .joinedAt
    @State private var layoutMode: LayoutMode = .single

    @Binding var newAccountName: String
    @Binding var newAccountQuota: Int

    let accounts: [AgentAccount]
    let switchLaunchError: String?
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
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                headerRow

                if showAddAccountControls {
                    PanelAdaptiveActionRowView {
                        addRow
                    }
                }

                if let switchLaunchError, !switchLaunchError.isEmpty {
                    PanelStatusCalloutView(
                        message: switchLaunchError,
                        title: "Switch Failed",
                        tone: .danger
                    )
                }

                ScrollView {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
                        ForEach(sortedAccounts) { account in
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

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Account Usage")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(PoolDashboardTheme.groupLabelOpacity))

            Spacer(minLength: 0)

            sortingLayoutControls
        }
    }

    private var sortingLayoutControls: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(SortMode.allCases) { mode in
                    Button {
                        sortMode = mode
                    } label: {
                        if sortMode == mode {
                            Label(mode.rawValue, systemImage: "checkmark")
                        } else {
                            Text(mode.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("排序")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption)
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(PoolDashboardTheme.panelMutedFill.opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(PoolDashboardTheme.panelInnerStroke.opacity(0.7), lineWidth: 0.8)
                        )
                )
            }
            .menuStyle(.borderlessButton)

            Picker("排列", selection: $layoutMode) {
                ForEach(LayoutMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
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

    private var sortedAccounts: [AgentAccount] {
        switch sortMode {
        case .joinedAt:
            return accounts.sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.createdAt > rhs.createdAt
            }
        case .name:
            return accounts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .remainingHigh:
            return accounts.sorted { lhs, rhs in
                if lhs.isUsageSyncExcluded != rhs.isUsageSyncExcluded {
                    return !lhs.isUsageSyncExcluded
                }
                if lhs.remainingRatio == rhs.remainingRatio {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.remainingRatio > rhs.remainingRatio
            }
        }
    }

    private func accountCard(_ account: AgentAccount) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if layoutMode == .single {
                accountNameRow(account)
                accountActionAndWarningRow(account)
            } else {
                accountNameRow(account)
                accountActionAndWarningRow(account)
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

    private func accountNameRow(_ account: AgentAccount) -> some View {
        TextField("Account name", text: accountNameBinding(account.id))
            .dashboardInputFieldStyle()
    }

    @ViewBuilder
    private func syncExcludedWarning(_ account: AgentAccount) -> some View {
        if account.isUsageSyncExcluded {
            PanelStatusCalloutView(
                message: account.usageSyncError ?? "This account is excluded from sync and pool calculations.",
                title: "Excluded from Sync",
                tone: .warning
            )
            .frame(maxWidth: 440, alignment: .leading)
        }
    }

    private func accountActionButtons(_ account: AgentAccount) -> some View {
        HStack(spacing: 8) {
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

    private func accountActionAndWarningRow(_ account: AgentAccount) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                syncExcludedWarning(account)
                Spacer(minLength: 0)
                accountActionButtons(account)
            }

            VStack(alignment: .leading, spacing: 8) {
                syncExcludedWarning(account)
                HStack {
                    Spacer(minLength: 0)
                    accountActionButtons(account)
                }
            }
        }
    }
}
