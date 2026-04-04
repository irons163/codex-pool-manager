import SwiftUI

struct AccountUsagePanelView: View {
    private enum SortMode: String, CaseIterable, Identifiable {
        case joinedAt
        case name
        case remainingHigh

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .joinedAt: L10n.text("sort.joined_at")
            case .name: L10n.text("sort.name")
            case .remainingHigh: L10n.text("sort.remaining_high")
            }
        }
    }

    private enum LayoutMode: String, CaseIterable, Identifiable {
        case single
        case double
        case triple
        case quad

        var id: String {
            rawValue
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

    @AppStorage("pool_dashboard.account_usage.sort_mode")
    private var persistedSortModeRawValue: String = SortMode.joinedAt.rawValue
    @AppStorage("pool_dashboard.account_usage.active_first")
    private var persistedActiveAccountFirst: Bool = true
    @AppStorage("pool_dashboard.account_usage.layout_mode")
    private var persistedLayoutModeRawValue: String = LayoutMode.single.rawValue
    @State private var newGroupName = ""
    @State private var renameGroupName = ""
    @State private var isGroupRenameEditorVisible = false
    @State private var draftAccountNames: [UUID: String] = [:]
    @FocusState private var focusedAccountNameID: UUID?

    @Binding var newAccountName: String
    @Binding var newAccountQuota: Int
    @Binding var selectedGroupName: String

    let accounts: [AgentAccount]
    let groups: [String]
    let activeAccountID: UUID?
    let switchLaunchError: String?
    let switchLaunchWarning: String?
    let showAddAccountControls: Bool
    let onAddAccount: (String, Int) -> Void
    let onSwitchAndLaunch: (AgentAccount) async -> Void
    let onRemoveAccount: (UUID) -> Void
    let onMoveAccountToGroup: (UUID, String) -> Void
    let onCreateGroup: (String) -> Void
    let onRenameGroup: (String, String) -> Void

    let accountNameBinding: (UUID) -> Binding<String>
    let accountQuotaBinding: (UUID) -> Binding<Int>
    let accountUsedBinding: (UUID) -> Binding<Int>

    let isPercentUsageAccount: (AgentAccount) -> Bool
    let remainingLabel: (AgentAccount) -> String
    let usageProgressColor: (AgentAccount) -> Color

    private var sortMode: SortMode {
        SortMode(rawValue: persistedSortModeRawValue) ?? .joinedAt
    }

    private var layoutMode: LayoutMode {
        LayoutMode(rawValue: persistedLayoutModeRawValue) ?? .single
    }

    private var layoutModeBinding: Binding<LayoutMode> {
        Binding(
            get: { layoutMode },
            set: { persistedLayoutModeRawValue = $0.rawValue }
        )
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                headerRow
                groupManagerRow

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
                if groups.isEmpty {
                    selectedGroupName = AgentAccount.defaultGroupName
                } else if !groups.contains(where: { $0.caseInsensitiveCompare(selectedGroupName) == .orderedSame }) {
                    selectedGroupName = groups[0]
                }
                renameGroupName = selectedGroupName
            }
        }
        .onChange(of: selectedGroupName) { _, value in
            renameGroupName = value
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
            Toggle(isOn: $persistedActiveAccountFirst) {
                Text(L10n.text("sort.active_first"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textSecondary)
            }
            .toggleStyle(.checkbox)

            Menu {
                ForEach(SortMode.allCases) { mode in
                    Button {
                        persistedSortModeRawValue = mode.rawValue
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

            Picker(L10n.text("layout.title"), selection: layoutModeBinding) {
                ForEach(LayoutMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var groupManagerRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(L10n.text("group.title"))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(PoolDashboardTheme.textPrimary)

                Picker("", selection: $selectedGroupName) {
                    ForEach(groups, id: \.self) { group in
                        Text(group).tag(group)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel(L10n.text("group.title"))

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isGroupRenameEditorVisible.toggle()
                        if isGroupRenameEditorVisible {
                            renameGroupName = selectedGroupName
                        }
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PoolDashboardTheme.glowA)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(PoolDashboardTheme.panelMutedFill.opacity(0.85))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(PoolDashboardTheme.panelInnerStroke.opacity(0.75), lineWidth: 0.8)
                                )
                        )
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .disabled(selectedGroupName.isEmpty)
                .help(L10n.text("group.rename"))
            }
            .fixedSize(horizontal: true, vertical: false)

            if isGroupRenameEditorVisible {
                TextField(L10n.text("group.rename"), text: $renameGroupName)
                    .dashboardInputFieldStyle()
                    .frame(maxWidth: 180)

                Button(L10n.text("group.rename_action")) {
                    let draft = renameGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !draft.isEmpty else { return }
                    let previous = selectedGroupName
                    onRenameGroup(previous, draft)
                    selectedGroupName = draft
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isGroupRenameEditorVisible = false
                    }
                }
                .buttonStyle(.bordered)
                .disabled(selectedGroupName.isEmpty)
            }

            TextField(L10n.text("group.placeholder"), text: $newGroupName)
                .dashboardInputFieldStyle()
                .frame(maxWidth: 180)

            Button(L10n.text("group.add")) {
                let draft = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !draft.isEmpty else { return }
                onCreateGroup(draft)
                selectedGroupName = draft
                newGroupName = ""
            }
            .buttonStyle(.borderedProminent)
            .tint(PoolDashboardTheme.glowA)

            if !outsideGroupAccounts.isEmpty {
                Menu {
                    ForEach(outsideGroupAccounts) { account in
                        Button("\(account.name) (\(account.groupName))") {
                            onMoveAccountToGroup(account.id, selectedGroupName)
                        }
                    }
                } label: {
                    Text(L10n.text("group.add_existing"))
                }
                .menuStyle(.borderlessButton)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var addRow: some View {
        HStack(spacing: PoolDashboardTheme.accountAddRowSpacing) {
            TextField(L10n.text("add.new_account_name"), text: $newAccountName)
                .dashboardInputFieldStyle()

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
        let filteredAccounts = accounts.filter {
            AgentAccount.normalizedGroupName($0.groupName).caseInsensitiveCompare(selectedGroupName) == .orderedSame
        }

        let baseSorted: [AgentAccount]
        switch sortMode {
        case .joinedAt:
            baseSorted = filteredAccounts.sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.createdAt > rhs.createdAt
            }
        case .name:
            baseSorted = filteredAccounts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .remainingHigh:
            baseSorted = filteredAccounts.sorted { lhs, rhs in
                if lhs.isUsageSyncExcluded != rhs.isUsageSyncExcluded {
                    return !lhs.isUsageSyncExcluded
                }
                if lhs.remainingRatio == rhs.remainingRatio {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.remainingRatio > rhs.remainingRatio
            }
        }

        guard persistedActiveAccountFirst,
              let activeAccountID,
              let activeIndex = baseSorted.firstIndex(where: { $0.id == activeAccountID }) else {
            return baseSorted
        }

        var reordered = baseSorted
        let activeAccount = reordered.remove(at: activeIndex)
        reordered.insert(activeAccount, at: 0)
        return reordered
    }

    private var outsideGroupAccounts: [AgentAccount] {
        accounts.filter {
            AgentAccount.normalizedGroupName($0.groupName).caseInsensitiveCompare(selectedGroupName) != .orderedSame
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
                if let fiveHourPercent = account.primaryUsagePercent {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            paidWeeklyUsageSection(for: account)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            paidFiveHourUsageSection(for: account, fiveHourPercent: fiveHourPercent)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            paidWeeklyUsageSection(for: account)
                            paidFiveHourUsageSection(for: account, fiveHourPercent: fiveHourPercent)
                        }
                    }
                } else {
                    paidWeeklyUsageSection(for: account)
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

            Text("\(L10n.text("group.title")): \(account.groupName)")
                .font(.caption)
                .foregroundStyle(PoolDashboardTheme.textMuted)
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

    private func weeklyRemainingRecordText(for account: AgentAccount) -> String? {
        guard isPaidAccount(account) else { return nil }

        if isPercentUsageAccount(account) {
            let used = max(0, min(100, account.usedUnits))
            return L10n.text("usage.remaining_percent_format", 100 - used)
        } else {
            return L10n.text("usage.remaining_units_format", account.remainingUnits)
        }
    }

    private func fiveHourRemainingRecordText(fiveHourPercent: Int) -> String {
        let used = max(0, min(100, fiveHourPercent))
        return L10n.text("usage.remaining_percent_format", 100 - used)
    }

    @ViewBuilder
    private func paidWeeklyUsageSection(for account: AgentAccount) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let weeklyUsageRecordText = weeklyUsageRecordText(for: account),
               let weeklyRemainingRecordText = weeklyRemainingRecordText(for: account) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(weeklyUsageRecordText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PoolDashboardTheme.textPrimary)
                    Text(weeklyRemainingRecordText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PoolDashboardTheme.textPrimary)
                }
            } else if let weeklyUsageRecordText = weeklyUsageRecordText(for: account) {
                Text(weeklyUsageRecordText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textPrimary)
            }
            ProgressView(value: account.usageRatio)
                .tint(usageProgressColor(account))
            Text(resetRecordText(for: account))
                .font(.footnote)
                .foregroundStyle(PoolDashboardTheme.textMuted)
        }
    }

    @ViewBuilder
    private func paidFiveHourUsageSection(for account: AgentAccount, fiveHourPercent: Int) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(L10n.text("account.five_hour_usage_percent_format", fiveHourPercent))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textPrimary)
                Text(fiveHourRemainingRecordText(fiveHourPercent: fiveHourPercent))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textPrimary)
            }
            ProgressView(value: Double(fiveHourPercent) / 100)
                .tint(usageColor(forPercent: fiveHourPercent))
                .frame(maxWidth: .infinity)
            Text(fiveHourResetRecordText(for: account))
                .font(.footnote)
                .foregroundStyle(PoolDashboardTheme.textMuted)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func resetRecordText(for account: AgentAccount) -> String {
        let resetText = account.usageWindowResetAt.map(localizedMonthDayHourMinuteText) ?? "--"
        return L10n.text("account.weekly_resets_format", resetText)
    }

    private func fiveHourResetRecordText(for account: AgentAccount) -> String {
        let resetText = account.primaryUsageResetAt.map(localizedMonthDayHourMinuteText) ?? "--"
        return L10n.text("account.five_hour_resets_format", resetText)
    }

    private func localizedMonthDayHourMinuteText(_ date: Date) -> String {
        date.formatted(.dateTime.locale(L10n.locale()).month().day().hour().minute())
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
