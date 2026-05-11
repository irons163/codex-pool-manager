import SwiftUI

struct AccountUsagePanelView: View {
    private enum DeleteConfirmationTarget: Identifiable {
        case group(name: String)
        case account(id: UUID, name: String)

        var id: String {
            switch self {
            case let .group(name):
                return "group:\(name)"
            case let .account(id, _):
                return "account:\(id.uuidString)"
            }
        }
    }

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
        case minimal

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .single: L10n.text("layout.single")
            case .double: L10n.text("layout.double")
            case .triple: L10n.text("layout.triple")
            case .quad: L10n.text("layout.quad")
            case .minimal: L10n.text("layout.minimal")
            }
        }

        var fixedColumns: Int? {
            switch self {
            case .single: return 1
            case .double: return 2
            case .triple: return 3
            case .quad: return 4
            case .minimal: return nil
            }
        }
    }

    @AppStorage("pool_dashboard.account_usage.sort_mode")
    private var persistedSortModeRawValue: String = SortMode.joinedAt.rawValue
    @AppStorage("pool_dashboard.account_usage.active_first")
    private var persistedActiveAccountFirst: Bool = true
    @AppStorage("pool_dashboard.account_usage.paid_first")
    private var persistedPaidAccountFirst: Bool = false
    @AppStorage("pool_dashboard.account_usage.layout_mode")
    private var persistedLayoutModeRawValue: String = LayoutMode.single.rawValue
    @State private var newGroupName = ""
    @State private var renameGroupName = ""
    @State private var isGroupRenameEditorVisible = false
    @State private var deleteConfirmationTarget: DeleteConfirmationTarget?
    @State private var draftAccountNames: [UUID: String] = [:]
    @State private var gridContainerWidth: CGFloat = 0
    @FocusState private var focusedAccountNameID: UUID?
    @FocusState private var isRenameGroupNameFocused: Bool
    @FocusState private var isNewGroupNameFocused: Bool

    private let accountGridSpacing: CGFloat = 10
    private let minimalCardMinWidth: CGFloat = 190
    private let minimalCardMaxWidth: CGFloat = 300

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
    let onDeleteGroup: (String) -> Void

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

    private var canDeleteSelectedGroup: Bool {
        let normalized = AgentAccount.normalizedGroupName(selectedGroupName)
        return !selectedGroupName.isEmpty
            && normalized.caseInsensitiveCompare(AgentAccount.defaultGroupName) != .orderedSame
    }

    private var activeAccount: AgentAccount? {
        guard let activeAccountID else { return nil }
        return accounts.first(where: { $0.id == activeAccountID })
    }

    private var selectedGroupHasCurrentAccount: Bool {
        groupContainsCurrentAccount(named: selectedGroupName)
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

                GeometryReader { proxy in
                    let availableWidth = max(0, proxy.size.width)
                    ScrollView {
                        LazyVGrid(columns: gridColumns(for: availableWidth), alignment: .leading, spacing: accountGridSpacing) {
                            ForEach(sortedAccounts) { account in
                                accountCard(account)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onAppear {
                            gridContainerWidth = availableWidth
                        }
                        .onChange(of: availableWidth) { _, newWidth in
                            gridContainerWidth = newWidth
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
                isRenameGroupNameFocused = false
                isNewGroupNameFocused = false
                if groups.isEmpty {
                    selectedGroupName = AgentAccount.defaultGroupName
                } else if !groups.contains(selectedGroupName) {
                    selectedGroupName = groups[0]
                }
                renameGroupName = selectedGroupName
            }
        }
        .onChange(of: selectedGroupName) { _, value in
            renameGroupName = value
        }
        .alert(item: $deleteConfirmationTarget) { target in
            Alert(
                title: Text(title(for: target)),
                message: Text(message(for: target)),
                primaryButton: .destructive(Text(L10n.text("delete.button"))) {
                    confirmDelete(target)
                },
                secondaryButton: .cancel(Text(L10n.text("account.edit.cancel")))
            )
        }
    }

    private var headerRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                Text(L10n.text("account_usage.title"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(PoolDashboardTheme.textPrimary.opacity(PoolDashboardTheme.groupLabelOpacity))

                Spacer(minLength: 0)

                sortingLayoutControls
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("account_usage.title"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(PoolDashboardTheme.textPrimary.opacity(PoolDashboardTheme.groupLabelOpacity))

                sortingLayoutControls
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var sortingLayoutControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                sortPriorityToggles
                sortAndLayoutControls
            }
            VStack(alignment: .trailing, spacing: 8) {
                sortPriorityToggles
                sortAndLayoutControls
            }
        }
    }

    private var sortPriorityToggles: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $persistedActiveAccountFirst) {
                Text(L10n.text("sort.active_first"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textSecondary)
                    .lineLimit(1)
            }
            .toggleStyle(.checkbox)
            .fixedSize(horizontal: true, vertical: false)

            Toggle(isOn: $persistedPaidAccountFirst) {
                Text(L10n.text("sort.paid_first"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textSecondary)
                    .lineLimit(1)
            }
            .toggleStyle(.checkbox)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var sortAndLayoutControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                sortMenuControl
                layoutModePicker
            }
            VStack(alignment: .trailing, spacing: 8) {
                sortMenuControl
                layoutModePicker
            }
        }
    }

    private var sortMenuControl: some View {
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
    }

    private var layoutModePicker: some View {
        Picker(L10n.text("layout.title"), selection: layoutModeBinding) {
            ForEach(LayoutMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var groupManagerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    groupSelectionControls

                    if isGroupRenameEditorVisible {
                        renameGroupControls
                    }

                    newGroupControls

                    addExistingAccountMenu
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        groupSelectionControls
                        if isGroupRenameEditorVisible {
                            renameGroupControls
                        }
                    }

                    HStack(spacing: 10) {
                        newGroupControls
                        addExistingAccountMenu
                    }
                }
            }

            if let activeAccount, !selectedGroupHasCurrentAccount {
                Button {
                    selectedGroupName = AgentAccount.normalizedGroupName(activeAccount.groupName)
                } label: {
                    Text("\(L10n.text("account.current_badge")): \(activeAccount.name) (\(activeAccount.groupName))")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help(L10n.text("account.current_badge"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var groupSelectionControls: some View {
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
                        isRenameGroupNameFocused = true
                    } else {
                        isRenameGroupNameFocused = false
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

            Button {
                requestDeleteSelectedGroup()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.9))
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
            .disabled(!canDeleteSelectedGroup)
            .help(L10n.text("group.delete"))
        }
    }

    private var renameGroupControls: some View {
        HStack(spacing: 8) {
            TextField(L10n.text("group.rename"), text: $renameGroupName)
                .focused($isRenameGroupNameFocused)
                .dashboardInputFieldStyle()
                .frame(minWidth: 100, idealWidth: 100, maxWidth: 220)
                .layoutPriority(1)

            Button(L10n.text("group.rename_action")) {
                let draft = renameGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !draft.isEmpty else { return }
                let previous = selectedGroupName
                onRenameGroup(previous, draft)
                selectedGroupName = draft
                withAnimation(.easeInOut(duration: 0.2)) {
                    isGroupRenameEditorVisible = false
                    isRenameGroupNameFocused = false
                }
            }
            .buttonStyle(.bordered)
            .disabled(selectedGroupName.isEmpty)
        }
    }

    private var newGroupControls: some View {
        HStack(spacing: 8) {
            TextField(L10n.text("group.placeholder"), text: $newGroupName)
                .focused($isNewGroupNameFocused)
                .dashboardInputFieldStyle()
                .frame(minWidth: 100, idealWidth: 100, maxWidth: 220)
                .layoutPriority(1)

            Button(L10n.text("group.add")) {
                let draft = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !draft.isEmpty else { return }
                onCreateGroup(draft)
                selectedGroupName = draft
                newGroupName = ""
            }
            .buttonStyle(.borderedProminent)
            .tint(PoolDashboardTheme.glowA)
        }
    }

    @ViewBuilder
    private var addExistingAccountMenu: some View {
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

    private func groupContainsCurrentAccount(named groupName: String) -> Bool {
        let normalizedGroupName = AgentAccount.normalizedGroupName(groupName)
        return accounts.contains { account in
            AgentAccount.normalizedGroupName(account.groupName) == normalizedGroupName
                && isCurrentEquivalentAccount(account)
        }
    }

    private func isCurrentEquivalentAccount(_ account: AgentAccount) -> Bool {
        guard let activeAccount else { return false }
        if activeAccount.id == account.id { return true }

        if identifiersMatch(activeAccount.chatGPTAccountID, account.chatGPTAccountID),
           activeAccount.identityScope == account.identityScope {
            return true
        }

        if !activeAccount.apiToken.isEmpty,
           !account.apiToken.isEmpty,
           activeAccount.apiToken == account.apiToken {
            return true
        }

        return false
    }

    private func identifiersMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = normalizedIdentifier(lhs),
              let rhs = normalizedIdentifier(rhs) else {
            return false
        }
        return lhs == rhs
    }

    private func normalizedIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
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

    private func gridColumns(for availableWidth: CGFloat) -> [GridItem] {
        if layoutMode == .minimal {
            guard availableWidth > 0 else {
                return [GridItem(.adaptive(minimum: minimalCardMinWidth, maximum: minimalCardMaxWidth), spacing: accountGridSpacing)]
            }

            let columns = max(1, Int((availableWidth + accountGridSpacing) / (minimalCardMinWidth + accountGridSpacing)))
            let totalSpacing = accountGridSpacing * CGFloat(max(0, columns - 1))
            let computedWidth = (availableWidth - totalSpacing) / CGFloat(columns)
            let itemWidth = min(minimalCardMaxWidth, max(minimalCardMinWidth, computedWidth))

            return Array(
                repeating: GridItem(.fixed(itemWidth), spacing: accountGridSpacing, alignment: .topLeading),
                count: columns
            )
        }

        guard let fixedColumns = layoutMode.fixedColumns else {
            return [GridItem(.adaptive(minimum: minimalCardMinWidth, maximum: minimalCardMaxWidth), spacing: accountGridSpacing)]
        }

        return Array(
            repeating: GridItem(.flexible(minimum: 220), spacing: accountGridSpacing),
            count: fixedColumns
        )
    }

    private var sortedAccounts: [AgentAccount] {
        let selectedGroup = AgentAccount.normalizedGroupName(selectedGroupName)
        let filteredAccounts = accounts.filter {
            AgentAccount.normalizedGroupName($0.groupName) == selectedGroup
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

        var reordered = baseSorted

        if persistedPaidAccountFirst {
            reordered = reordered.stablePartitioned { $0.isPaid }
        }

        if persistedActiveAccountFirst,
           let activeIndex = reordered.firstIndex(where: isCurrentEquivalentAccount) {
            let activeAccount = reordered.remove(at: activeIndex)
            reordered.insert(activeAccount, at: 0)
        }

        return reordered
    }

    private var outsideGroupAccounts: [AgentAccount] {
        let selectedGroup = AgentAccount.normalizedGroupName(selectedGroupName)
        return accounts.filter {
            AgentAccount.normalizedGroupName($0.groupName) != selectedGroup
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func accountCard(_ account: AgentAccount) -> some View {
        let isCurrentAccount = isCurrentEquivalentAccount(account)
        return VStack(alignment: .leading, spacing: 8) {
            if layoutMode == .minimal {
                minimalAccountCardContent(account)
            } else {
                fullAccountCardContent(account)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .shadow(
            color: (isCurrentAccount && !PoolDashboardTheme.isLightPalette) ? PoolDashboardTheme.glowA.opacity(0.35) : .clear,
            radius: (isCurrentAccount && !PoolDashboardTheme.isLightPalette) ? 12 : 0
        )
    }

    @ViewBuilder
    private func fullAccountCardContent(_ account: AgentAccount) -> some View {
        let paidAccount = isPaidAccount(account)
        accountNameRow(account)
        accountActionAndWarningRow(account)

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

    @ViewBuilder
    private func minimalAccountCardContent(_ account: AgentAccount) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Text(account.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 6) {
                if isPaidAccount(account) {
                    Text(L10n.text("account.paid_badge"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PoolDashboardTheme.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.orange.opacity(0.28))
                        )
                }

                compactAccountActionButtons(account)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .top, spacing: 10) {
                circularUsageIndicator(
                    title: L10n.text("usage.weekly_short"),
                    usedPercent: weeklyUsagePercent(for: account),
                    color: usageProgressColor(account),
                    resetText: shortResetDateText(account.usageWindowResetAt)
                )

                if isPaidAccount(account), let fiveHourPercent = account.primaryUsagePercent {
                    circularUsageIndicator(
                        title: L10n.text("usage.five_hour_short"),
                        usedPercent: max(0, min(100, fiveHourPercent)),
                        color: usageColor(forPercent: fiveHourPercent),
                        resetText: shortResetDateText(account.primaryUsageResetAt)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }

        if account.isUsageSyncExcluded {
            syncExcludedWarning(account)
        }
    }

    private func compactAccountActionButtons(_ account: AgentAccount) -> some View {
        HStack(spacing: 6) {
            Button(L10n.text("switch.launch.button")) {
                Task {
                    await onSwitchAndLaunch(account)
                }
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .tint(PoolDashboardTheme.glowA)

            Button(L10n.text("delete.button"), role: .destructive) {
                deleteConfirmationTarget = .account(id: account.id, name: account.name)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        }
    }

    private func weeklyUsagePercent(for account: AgentAccount) -> Int {
        if isPercentUsageAccount(account) {
            return max(0, min(100, account.usedUnits))
        }
        return max(0, min(100, Int((account.usageRatio * 100).rounded())))
    }

    private func circularUsageIndicator(
        title: String,
        usedPercent: Int,
        color: Color,
        resetText: String
    ) -> some View {
        let clampedUsedPercent = max(0, min(100, usedPercent))
        let remainingPercent = max(0, min(100, 100 - clampedUsedPercent))

        return VStack(alignment: .center, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PoolDashboardTheme.textSecondary)

            ZStack {
                Circle()
                    .stroke(PoolDashboardTheme.panelInnerStroke.opacity(0.75), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: Double(clampedUsedPercent) / 100)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(remainingPercent)%")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(PoolDashboardTheme.textPrimary)
                    Text(L10n.text("usage.left_short"))
                        .font(.caption2)
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                }
            }
            .frame(width: 64, height: 64)

            Text(resetText)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(PoolDashboardTheme.textMuted)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func shortResetDateText(_ date: Date?) -> String {
        date.map(localizedMonthDayHourMinuteText) ?? "--"
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

                if isCurrentEquivalentAccount(account) {
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

    private func requestDeleteSelectedGroup() {
        guard canDeleteSelectedGroup else { return }
        deleteConfirmationTarget = .group(name: selectedGroupName)
    }

    private func title(for target: DeleteConfirmationTarget) -> String {
        switch target {
        case .group:
            return L10n.text("group.delete_confirm_title")
        case .account:
            return L10n.text("account.delete_confirm_title")
        }
    }

    private func message(for target: DeleteConfirmationTarget) -> String {
        switch target {
        case let .group(name):
            return L10n.text("group.delete_confirm_message_format", name)
        case let .account(_, name):
            return L10n.text("account.delete_confirm_message_format", name)
        }
    }

    private func confirmDelete(_ target: DeleteConfirmationTarget) {
        switch target {
        case let .group(name):
            let targetGroup = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !targetGroup.isEmpty else { return }
            onDeleteGroup(targetGroup)
            withAnimation(.easeInOut(duration: 0.2)) {
                isGroupRenameEditorVisible = false
                isRenameGroupNameFocused = false
            }
        case let .account(id, _):
            onRemoveAccount(id)
        }
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
                deleteConfirmationTarget = .account(id: account.id, name: account.name)
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

private extension Array {
    func stablePartitioned(by predicate: (Element) -> Bool) -> [Element] {
        var matching: [Element] = []
        var nonMatching: [Element] = []
        matching.reserveCapacity(count)
        nonMatching.reserveCapacity(count)

        for element in self {
            if predicate(element) {
                matching.append(element)
            } else {
                nonMatching.append(element)
            }
        }

        return matching + nonMatching
    }
}
