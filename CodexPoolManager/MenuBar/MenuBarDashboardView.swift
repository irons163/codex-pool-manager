import SwiftUI

struct MenuBarDashboardView: View {
    @ObservedObject var runtimeModel: AppPoolRuntimeModel
    @State private var isWarningPopoverPresented = false
    @State private var selectedAccountGroupName: String?

    let openDashboard: () -> Void
    let switchAccount: (UUID) -> Void

    private static let allAccountGroupsSelection = ""

    private var snapshot: MenuBarDashboardSnapshot {
        runtimeModel.menuBarSnapshot
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if snapshot.accountRows.isEmpty {
                    emptyState
                } else {
                    accountsSection
                }
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
        .frame(width: 390)
        .frame(minHeight: 420, maxHeight: 620)
        .background(background)
        .task {
            runtimeModel.bootstrapIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.95),
                                    Color.cyan.opacity(0.78)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("menu_bar.header.title"))
                        .font(.title3.weight(.semibold))
                    Text(snapshot.headerSummaryText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 0)

                warningPopoverButton
            }

            HStack(spacing: 8) {
                Button {
                    Task { @MainActor in
                        await runtimeModel.syncNowWithTimeout()
                    }
                } label: {
                    Label(
                        L10n.text("menu_bar.action.sync_now"),
                        systemImage: snapshot.isSyncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise"
                    )
                }
                .disabled(snapshot.isSyncing)

                Button {
                    openDashboard()
                } label: {
                    Label(L10n.text("menu_bar.action.open_dashboard"), systemImage: "rectangle.3.group")
                }
            }
            .buttonStyle(.bordered)

            HStack(spacing: 6) {
                if snapshot.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(snapshot.updatedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var warningPopoverButton: some View {
        if !snapshot.warningRows.isEmpty {
            Button {
                isWarningPopoverPresented.toggle()
            } label: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .frame(width: 28, height: 28)
                    .background(.regularMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.16), lineWidth: 0.8)
                    }
            }
            .buttonStyle(.plain)
            .help(L10n.text("menu_bar.section.warnings"))
            .accessibilityLabel(L10n.text("menu_bar.section.warnings"))
            .popover(isPresented: $isWarningPopoverPresented, arrowEdge: .bottom) {
                WarningsPopoverView(rows: snapshot.warningRows)
            }
        }
    }

    private var accountsSection: some View {
        SectionCard(title: L10n.text("menu_bar.section.accounts")) {
            accountGroupSwitcher
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(filteredAccountRows) { row in
                    AccountRowView(row: row, switchAccount: switchAccount)
                }
            }
        }
    }

    private var filteredAccountRows: [MenuBarAccountRow] {
        guard let groupName = selectedAccountGroupFilter else {
            return snapshot.accountRows
        }
        return snapshot.accountRows.filter { $0.groupName == groupName }
    }

    private var selectedAccountGroupFilter: String? {
        if selectedAccountGroupName == Self.allAccountGroupsSelection {
            return nil
        }

        if let selectedAccountGroupName,
           snapshot.accountGroupNames.contains(selectedAccountGroupName) {
            return selectedAccountGroupName
        }

        if let activeGroupName = snapshot.activeAccount?.groupName,
           snapshot.accountGroupNames.contains(activeGroupName) {
            return activeGroupName
        }

        return snapshot.accountGroupNames.first
    }

    private var selectedAccountGroupLabel: String {
        guard selectedAccountGroupName != Self.allAccountGroupsSelection else {
            return L10n.text("group.all")
        }
        return selectedAccountGroupFilter ?? L10n.text("group.all")
    }

    @ViewBuilder
    private var accountGroupSwitcher: some View {
        if snapshot.accountGroupNames.count > 1 {
            Menu {
                accountGroupOption(
                    title: L10n.text("group.all"),
                    selection: Self.allAccountGroupsSelection
                )

                Divider()

                ForEach(snapshot.accountGroupNames, id: \.self) { groupName in
                    accountGroupOption(title: groupName, selection: groupName)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                    Text(selectedAccountGroupLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: true, vertical: false)
            .help(L10n.text("group.title"))
            .accessibilityLabel(L10n.text("group.title"))
        }
    }

    private func accountGroupOption(title: String, selection: String) -> some View {
        Button {
            selectedAccountGroupName = selection
        } label: {
            if selectedAccountGroupNameForMenu == selection {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var selectedAccountGroupNameForMenu: String {
        selectedAccountGroupFilter ?? Self.allAccountGroupsSelection
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 4) {
                Text(L10n.text("menu_bar.empty.title"))
                    .font(.headline)
                Text(L10n.text("menu_bar.empty.message"))
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                openDashboard()
            } label: {
                Label(L10n.text("menu_bar.action.open_dashboard"), systemImage: "rectangle.3.group")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.10),
                    Color.cyan.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 180, height: 180)
                .blur(radius: 44)
                .offset(x: -150, y: -230)

            Circle()
                .fill(Color.cyan.opacity(0.10))
                .frame(width: 160, height: 160)
                .blur(radius: 40)
                .offset(x: 160, y: 260)
        }
    }
}

private struct SectionCard<HeaderAccessory: View, Content: View>: View {
    let title: String
    let headerAccessory: HeaderAccessory
    let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) where HeaderAccessory == EmptyView {
        self.title = title
        self.headerAccessory = EmptyView()
        self.content = content()
    }

    init(
        title: String,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.headerAccessory = headerAccessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Spacer(minLength: 8)

                headerAccessory
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.8)
        }
    }
}

private struct AccountRowView: View {
    @State private var isAccountWarningPopoverPresented = false
    @State private var isResetCreditNotePopoverPresented = false

    let row: MenuBarAccountRow
    let switchAccount: (UUID) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            activeIndicator

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(0)

                    if row.isPaid {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }

                    if let credentialLabel = row.credentialLabel {
                        Text(credentialLabel)
                            .font(.caption2.weight(.semibold))
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .background(Color.secondary.opacity(0.14), in: Capsule())
                    }

                    if let planBadgeText = row.planBadgeText {
                        Text(planBadgeText)
                            .font(.caption2.weight(.semibold))
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .background(Color.accentColor.opacity(0.16), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }

                    accountWarningIndicator

                    Spacer(minLength: 8)

                    accountAction
                        .fixedSize()
                }

                accountUsageResetLine

                resetCreditDetailLines
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var resetCreditDetailLines: some View {
        let detailLines = resetCreditDetailLineTexts

        if !detailLines.isEmpty {
            HStack(alignment: .top, spacing: 5) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(detailLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .foregroundStyle(index == 0 ? Color.accentColor : Color.secondary)
                    }
                }

                resetCreditNoteButton
            }
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .padding(.top, 1)
            .help(row.resetCreditDetailText ?? detailLines.joined(separator: "\n"))
            .accessibilityLabel(row.resetCreditAccessibilityLabel ?? detailLines.joined(separator: ", "))
        }
    }

    @ViewBuilder
    private var resetCreditNoteButton: some View {
        if let noteText = resetCreditNoteText {
            Button {
                isResetCreditNotePopoverPresented.toggle()
            } label: {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
                    .padding(.top, 1)
            }
            .buttonStyle(.plain)
            .help(noteText)
            .accessibilityLabel(noteText)
            .popover(isPresented: $isResetCreditNotePopoverPresented, arrowEdge: .bottom) {
                Text(noteText)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(width: 260, alignment: .leading)
            }
        }
    }

    private var resetCreditNoteText: String? {
        guard let noteText = row.resetCreditNoteText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !noteText.isEmpty else {
            return nil
        }

        return noteText
    }

    private var resetCreditDetailLineTexts: [String] {
        row.resetCreditDetailText?
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private var activeIndicator: some View {
        Circle()
            .fill(row.isActive ? Color.accentColor : Color.secondary.opacity(0.35))
            .frame(width: 8, height: 8)
    }

    @ViewBuilder
    private var accountWarningIndicator: some View {
        if let warningText = row.warningText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !warningText.isEmpty {
            Button {
                isAccountWarningPopoverPresented.toggle()
            } label: {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help(warningText)
            .accessibilityLabel(warningText)
            .popover(isPresented: $isAccountWarningPopoverPresented, arrowEdge: .bottom) {
                Text(warningText)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(width: 260, alignment: .leading)
            }
        }
    }

    private var accountUsageResetLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            accountUsageResetPair(
                scope: "W",
                remainingText: row.weeklyRemainingText,
                resetText: row.resetText
            )

            if let fiveHourRemainingText = row.fiveHourRemainingText {
                Text("·")
                    .foregroundStyle(.tertiary)

                accountUsageResetPair(
                    scope: "5h",
                    remainingText: fiveHourRemainingText,
                    resetText: row.fiveHourResetText ?? "—"
                )
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .layoutPriority(1)
    }

    private func accountUsageResetPair(
        scope: String,
        remainingText: String,
        resetText: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(scope)
                .foregroundStyle(.tertiary)
                .frame(minWidth: scope == "5h" ? 15 : 10, alignment: .leading)

            Text(remainingText)
                .foregroundStyle(.secondary)

            Text(resetText)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }

    @ViewBuilder
    private var accountAction: some View {
        if row.isActive {
            Image(systemName: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel(L10n.text("menu_bar.section.active"))
        } else {
            Button(L10n.text("menu_bar.action.switch")) {
                switchAccount(row.id)
            }
            .accessibilityLabel("\(L10n.text("menu_bar.action.switch")) \(row.name)")
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var rowBackground: some ShapeStyle {
        row.isActive ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.07)
    }
}

private struct WarningRowView: View {
    let row: MenuBarWarningRow

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(row.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var tint: Color {
        switch row.kind {
        case .oauthExpired, .syncFailed:
            return .orange
        case .relayUsageUnavailable:
            return .blue
        case .excluded:
            return .secondary
        }
    }

    private var systemImage: String {
        switch row.kind {
        case .oauthExpired:
            return "person.crop.circle.badge.exclamationmark"
        case .relayUsageUnavailable:
            return "key.horizontal"
        case .syncFailed:
            return "exclamationmark.triangle"
        case .excluded:
            return "minus.circle"
        }
    }
}

private struct WarningsPopoverView: View {
    let rows: [MenuBarWarningRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("menu_bar.section.warnings"))
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows) { row in
                        WarningRowView(row: row)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .frame(maxHeight: 360, alignment: .topLeading)
    }
}
