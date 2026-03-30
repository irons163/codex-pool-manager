import SwiftUI

struct AccountUsagePanelView: View {
    private enum GroupFilter: Identifiable, Equatable {
        case all
        case named(String)

        var id: String {
            switch self {
            case .all: "all"
            case .named(let value): value
            }
        }

        var title: String {
            switch self {
            case .all: L10n.text("group.all")
            case .named(let value): value
            }
        }
    }

    private enum SortMode: CaseIterable, Identifiable {
        case joinedAt
        case name
        case remainingHigh

        var id: String {
            switch self {
            case .joinedAt: "joinedAt"
            case .name: "name"
            case .remainingHigh: "remainingHigh"
            }
        }

        var title: String {
            switch self {
            case .joinedAt: L10n.text("sort.joined_at")
            case .name: L10n.text("sort.name")
            case .remainingHigh: L10n.text("sort.remaining_high")
            }
        }
    }

    private enum LayoutMode: CaseIterable, Identifiable {
        case single
        case double
        case triple
        case quad

        var id: String {
            switch self {
            case .single: "single"
            case .double: "double"
            case .triple: "triple"
            case .quad: "quad"
            }
        }

        var title: String {
            switch self {
            case .single: L10n.text("layout.single")
            case .double: L10n.text("layout.double")
            case .triple: L10n.text("layout.triple")
            case .quad: L10n.text("layout.quad")
            }
        }

        var columns: Int {
            switch self {
            case .single: 1
            case .double: 2
            case .triple: 3
            case .quad: 4
            }
        }
    }

    @State private var sortMode: SortMode = .joinedAt
    @State private var layoutMode: LayoutMode = .single
    @State private var selectedGroupFilter: GroupFilter = .all
    @State private var draftAccountNames: [UUID: String] = [:]
    @FocusState private var focusedAccountNameID: UUID?

    @Binding var newAccountName: String
    @Binding var newAccountGroup: String
    @Binding var newAccountQuota: Int

    let accounts: [AgentAccount]
    let activeAccountID: UUID?
    let switchLaunchError: String?
    let switchLaunchWarning: String?
    let showAddAccountControls: Bool
    let onAddAccount: (String, Int) -> Void
    let onSwitchAndLaunch: (AgentAccount) async -> Void
    let onRemoveAccount: (UUID) -> Void
    let onDuplicateAccount: (UUID) -> Void

    let accountNameBinding: (UUID) -> Binding<String>
    let accountGroupBinding: (UUID) -> Binding<String>
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

                if let switchLaunchWarning, !switchLaunchWarning.isEmpty {
                    PanelStatusCalloutView(
                        message: switchLaunchWarning,
                        title: L10n.text("switch.warning.title"),
                        tone: .warning
                    )
                }

                if let switchLaunchError, !switchLaunchError.isEmpty {
                    PanelStatusCalloutView(
                        message: switchLaunchError,
                        title: L10n.text("switch.failed.title"),
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
        .onAppear {
            DispatchQueue.main.async {
                focusedAccountNameID = nil
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(L10n.text("account_usage.title"))
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
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(L10n.text("sort.title"))
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

            Menu {
                Button {
                    selectedGroupFilter = .all
                } label: {
                    if selectedGroupFilter == .all {
                        Label(L10n.text("group.all"), systemImage: "checkmark")
                    } else {
                        Text(L10n.text("group.all"))
                    }
                }
                ForEach(groupNames, id: \.self) { groupName in
                    let filter = GroupFilter.named(groupName)
                    Button {
                        selectedGroupFilter = filter
                    } label: {
                        if selectedGroupFilter == filter {
                            Label(groupName, systemImage: "checkmark")
                        } else {
                            Text(groupName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(L10n.text("group.title"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                    Text(selectedGroupFilter.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                        .lineLimit(1)
                    Image(systemName: "line.3.horizontal.decrease.circle")
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

            Picker(L10n.text("layout.title"), selection: $layoutMode) {
                ForEach(LayoutMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var addRow: some View {
        HStack(spacing: PoolDashboardTheme.accountAddRowSpacing) {
            TextField(L10n.text("add.new_account_name"), text: $newAccountName)
                .dashboardInputFieldStyle()

            TextField(L10n.text("add.group_name"), text: $newAccountGroup)
                .dashboardInputFieldStyle()
                .frame(maxWidth: 160)

            Stepper(L10n.text("add.quota_format", newAccountQuota), value: $newAccountQuota, in: 100...10_000, step: 100)
                .monospacedDigit()

            Button(L10n.text("add.add_account")) {
                onAddAccount(
                    newAccountName.trimmingCharacters(in: .whitespacesAndNewlines),
                    newAccountQuota
                )
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
        let filteredAccounts: [AgentAccount]
        switch selectedGroupFilter {
        case .all:
            filteredAccounts = accounts
        case .named(let value):
            filteredAccounts = accounts.filter { AgentAccount.normalizedGroupName($0.groupName) == value }
        }

        switch sortMode {
        case .joinedAt:
            return filteredAccounts.sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.createdAt > rhs.createdAt
            }
        case .name:
            return filteredAccounts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .remainingHigh:
            return filteredAccounts.sorted { lhs, rhs in
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

    private var groupNames: [String] {
        Array(Set(accounts.map { AgentAccount.normalizedGroupName($0.groupName) }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func accountCard(_ account: AgentAccount) -> some View {
        let isCurrentAccount = activeAccountID == account.id
        let paidAccount = isPaidAccount(account)

        return VStack(alignment: .leading, spacing: 8) {
            if layoutMode == .single {
                accountNameRow(account)
                accountActionAndWarningRow(account)
            } else {
                accountNameRow(account)
                accountActionAndWarningRow(account)
            }

            if paidAccount {
                if let weeklyUsageRecordText = weeklyUsageRecordText(for: account) {
                    Text(weeklyUsageRecordText)
                        .font(.footnote)
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                }
                ProgressView(value: account.usageRatio)
                    .tint(usageProgressColor(account))
                Text(resetRecordText(for: account))
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                if let fiveHourPercent = account.primaryUsagePercent {
                    Text(L10n.text("account.five_hour_usage_percent_format", fiveHourPercent))
                        .font(.footnote)
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                    ProgressView(value: Double(fiveHourPercent) / 100)
                        .tint(usageColor(forPercent: fiveHourPercent))
                    Text(fiveHourResetRecordText(for: account))
                        .font(.footnote)
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                }
            } else {
                if isPercentUsageAccount(account) {
                    HStack {
                        Text(L10n.text("usage.used_percent_format", account.usedUnits))
                            .font(.subheadline)
                        Spacer()
                        Text(L10n.text("usage.remaining_percent_format", account.remainingUnits))
                            .font(.subheadline)
                    }
                } else {
                    HStack {
                        Stepper(
                            L10n.text("usage.used_units_format", account.usedUnits),
                            value: accountUsedBinding(account.id),
                            in: 0...account.quota,
                            step: 50
                        )
                        Stepper(
                            L10n.text("usage.quota_units_format", account.quota),
                            value: accountQuotaBinding(account.id),
                            in: 100...20_000,
                            step: 100
                        )
                    }
                }

                ProgressView(value: account.usageRatio)
                    .tint(usageProgressColor(account))
                Text(resetRecordText(for: account))
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .dashboardListRowCard()
        .overlay {
            if isCurrentAccount {
                RoundedRectangle(cornerRadius: PoolDashboardTheme.controlCornerRadius, style: .continuous)
                    .stroke(PoolDashboardTheme.glowA.opacity(0.92), lineWidth: 2.2)
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.controlCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                            .padding(1)
                    )
            }
        }
        .shadow(color: isCurrentAccount ? PoolDashboardTheme.glowA.opacity(0.35) : .clear, radius: isCurrentAccount ? 12 : 0)
    }

    private func accountNameRow(_ account: AgentAccount) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField(L10n.text("account.name.placeholder"), text: accountNameDraftBinding(account))
                    .focused($focusedAccountNameID, equals: account.id)
                    .onSubmit {
                        saveAccountName(account)
                    }
                    .dashboardInputFieldStyle()

                if isEditingAccountName(account) {
                    Button(L10n.text("account.edit.cancel")) {
                        cancelEditingAccountName(account)
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)

                    Button(L10n.text("account.edit.save")) {
                        saveAccountName(account)
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(PoolDashboardTheme.glowA)
                    .disabled(!hasPendingAccountNameChanges(account))
                }

                if activeAccountID == account.id {
                    Text(L10n.text("account.current_badge"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PoolDashboardTheme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(PoolDashboardTheme.glowA.opacity(0.34))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(PoolDashboardTheme.glowA.opacity(0.6), lineWidth: 0.8)
                        )
                }

                if isPaidAccount(account) {
                    Text(L10n.text("account.paid_badge"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PoolDashboardTheme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.orange.opacity(0.34))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.orange.opacity(0.6), lineWidth: 0.8)
                        )
                }
            }

            HStack(spacing: 8) {
                Text(L10n.text("group.title"))
                    .font(.caption)
                    .foregroundStyle(PoolDashboardTheme.textMuted)
                TextField(L10n.text("group.placeholder"), text: accountGroupBinding(account.id))
                    .dashboardInputFieldStyle()
                    .frame(maxWidth: 180)
            }
        }
    }

    @ViewBuilder
    private func accountEmailLabel(_ account: AgentAccount) -> some View {
        if let email = account.email, !email.isEmpty {
            Text(email)
                .font(.caption)
                .foregroundStyle(PoolDashboardTheme.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func accountNameDraftBinding(_ account: AgentAccount) -> Binding<String> {
        Binding(
            get: { draftAccountNames[account.id] ?? account.name },
            set: { draftAccountNames[account.id] = $0 }
        )
    }

    private func isEditingAccountName(_ account: AgentAccount) -> Bool {
        focusedAccountNameID == account.id
    }

    private func hasPendingAccountNameChanges(_ account: AgentAccount) -> Bool {
        (draftAccountNames[account.id] ?? account.name) != account.name
    }

    private func cancelEditingAccountName(_ account: AgentAccount) {
        draftAccountNames[account.id] = nil
        if focusedAccountNameID == account.id {
            focusedAccountNameID = nil
        }
    }

    private func saveAccountName(_ account: AgentAccount) {
        let draftName = (draftAccountNames[account.id] ?? account.name)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if draftName != account.name {
            accountNameBinding(account.id).wrappedValue = draftName
        }

        draftAccountNames[account.id] = nil
        if focusedAccountNameID == account.id {
            focusedAccountNameID = nil
        }
    }

    private func isPaidAccount(_ account: AgentAccount) -> Bool {
        account.isPaid
    }

    private func weeklyUsageRecordText(for account: AgentAccount) -> String? {
        guard isPaidAccount(account) else { return nil }

        if isPercentUsageAccount(account) {
            return L10n.text("account.weekly_usage_percent_format", account.usedUnits)
        } else {
            return L10n.text("account.weekly_usage_units_format", account.usedUnits, account.quota)
        }
    }

    private func resetRecordText(for account: AgentAccount) -> String {
        let resetText = account.usageWindowResetAt?
            .formatted(.dateTime.month().day().hour().minute()) ?? "--"
        return L10n.text("account.weekly_resets_format", resetText)
    }

    private func fiveHourResetRecordText(for account: AgentAccount) -> String {
        let resetText = account.primaryUsageResetAt?
            .formatted(.dateTime.month().day().hour().minute()) ?? "--"
        return L10n.text("account.five_hour_resets_format", resetText)
    }

    private func usageColor(forPercent percent: Int) -> Color {
        if percent >= 90 { return .red }
        if percent >= 70 { return .orange }
        return .blue
    }

    @ViewBuilder
    private func syncExcludedWarning(_ account: AgentAccount) -> some View {
        if account.isUsageSyncExcluded {
            PanelStatusCalloutView(
                message: account.usageSyncError ?? L10n.text("sync.excluded.default_message"),
                title: L10n.text("sync.excluded.title"),
                tone: .warning
            )
            .frame(maxWidth: 440, alignment: .leading)
        }
    }

    private func accountActionButtons(_ account: AgentAccount) -> some View {
        HStack(spacing: 8) {
            Button(L10n.text("duplicate.button")) {
                onDuplicateAccount(account.id)
            }
            .buttonStyle(.bordered)
            .lineLimit(1)
            .minimumScaleFactor(0.85)

            Button(L10n.text("switch.launch.button")) {
                Task {
                    await onSwitchAndLaunch(account)
                }
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .lineLimit(1)
            .minimumScaleFactor(0.85)

            Button(L10n.text("delete.button"), role: .destructive) {
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
                accountEmailLabel(account)
                Spacer(minLength: 0)
                accountActionButtons(account)
            }

            VStack(alignment: .leading, spacing: 8) {
                syncExcludedWarning(account)
                HStack(spacing: 10) {
                    accountEmailLabel(account)
                    Spacer(minLength: 0)
                    accountActionButtons(account)
                }
            }
        }
    }
}
