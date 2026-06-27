import Foundation

struct MenuBarDashboardSnapshot: Equatable {
    let title: String
    let totalAccountsText: String
    let availableAccountsText: String
    let usageText: String
    let modeText: String
    let updatedText: String
    let activeAccount: MenuBarAccountRow?
    let accountRows: [MenuBarAccountRow]
    let warningRows: [MenuBarWarningRow]
    let isSyncing: Bool
    let lastSyncError: String?
}

struct MenuBarAccountRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let isActive: Bool
    let isPaid: Bool
    let credentialLabel: String?
    let weeklyRemainingText: String
    let fiveHourRemainingText: String?
    let resetText: String
    let warningText: String?
}

struct MenuBarWarningRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case oauthExpired
        case relayUsageUnavailable
        case syncFailed
        case excluded
    }

    let id: String
    let kind: Kind
    let title: String
    let message: String
}

enum MenuBarDashboardPresenter {
    static func makeSnapshot(
        from state: AccountPoolState,
        isSyncing: Bool,
        lastSyncError: String?,
        now: Date = Date()
    ) -> MenuBarDashboardSnapshot {
        let accountRows = state.accounts.map { account in
            makeAccountRow(account, activeAccountID: state.activeAccountID, now: now)
        }
        let activeAccount = state.activeAccount.flatMap { active in
            accountRows.first(where: { $0.id == active.id })
        }
        let updatedAt = state.lastUsageSyncAt ?? now
        let bridgeSnapshot = MenuBarBridgeSnapshot(
            updatedAt: updatedAt,
            activeAccountName: state.activeAccount?.name,
            activeIsPaid: state.activeAccount?.isPaid,
            activeRemainingUnits: state.activeAccount?.remainingUnits,
            activeQuota: state.activeAccount?.quota,
            activeFiveHourRemainingPercent: remainingPercent(fromUsagePercent: state.activeAccount?.primaryUsagePercent),
            activeWeeklyResetAt: state.activeAccount?.usageWindowResetAt,
            activeFiveHourResetAt: state.activeAccount?.primaryUsageResetAt
        )

        return MenuBarDashboardSnapshot(
            title: MenuBarSnapshotFormatter.menuBarTitle(snapshot: bridgeSnapshot, now: now),
            totalAccountsText: String(state.accounts.count),
            availableAccountsText: String(state.availableAccountsCount),
            usageText: percentText(1 - state.overallUsageRatio),
            modeText: modeText(for: state.mode),
            updatedText: updatedText(since: state.lastUsageSyncAt, now: now),
            activeAccount: activeAccount,
            accountRows: accountRows,
            warningRows: warningRows(from: state, lastSyncError: lastSyncError),
            isSyncing: isSyncing,
            lastSyncError: lastSyncError
        )
    }

    private static func makeAccountRow(
        _ account: AgentAccount,
        activeAccountID: UUID?,
        now: Date
    ) -> MenuBarAccountRow {
        MenuBarAccountRow(
            id: account.id,
            name: account.name,
            isActive: account.id == activeAccountID,
            isPaid: account.isPaid,
            credentialLabel: account.isRelayAPIKeyAccount ? L10n.text("account.api_key_badge") : nil,
            weeklyRemainingText: percentText(account.remainingRatio),
            fiveHourRemainingText: remainingPercent(fromUsagePercent: account.primaryUsagePercent).map { "\($0)%" },
            resetText: resetText(for: account.usageWindowResetAt, now: now),
            warningText: account.usageSyncError
        )
    }

    private static func warningRows(
        from state: AccountPoolState,
        lastSyncError: String?
    ) -> [MenuBarWarningRow] {
        var rows: [MenuBarWarningRow] = []

        if let lastSyncError, !lastSyncError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows.append(MenuBarWarningRow(
                id: "syncFailed",
                kind: .syncFailed,
                title: L10n.text("menu_bar.warning.sync_failed.title"),
                message: lastSyncError
            ))
        }

        if state.accounts.contains(where: { isOAuthExpiredSyncError($0.usageSyncError) }) {
            rows.append(MenuBarWarningRow(
                id: "oauthExpired",
                kind: .oauthExpired,
                title: L10n.text("menu_bar.warning.oauth_expired.title"),
                message: L10n.text("menu_bar.warning.oauth_expired.message")
            ))
        }

        if state.accounts.contains(where: \.isRelayAPIKeyAccount) {
            rows.append(MenuBarWarningRow(
                id: "relayUsageUnavailable",
                kind: .relayUsageUnavailable,
                title: L10n.text("menu_bar.warning.relay_usage.title"),
                message: L10n.text("menu_bar.warning.relay_usage.message")
            ))
        }

        rows.append(contentsOf: state.accounts.compactMap { account in
            guard account.isUsageSyncExcluded, !account.isRelayAPIKeyAccount else {
                return nil
            }

            return MenuBarWarningRow(
                id: "excluded-\(account.id.uuidString)",
                kind: .excluded,
                title: account.name,
                message: excludedWarningMessage(for: account)
            )
        })

        return rows
    }

    private static func isOAuthExpiredSyncError(_ message: String?) -> Bool {
        guard let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return false
        }
        return oauthExpiredMessages().contains(trimmed)
    }

    private static func oauthExpiredMessages() -> Set<String> {
        let key = "usage.sync.error.oauth_login_expired"
        let supportedLanguageCodes = ["en", "zh-Hant", "zh-Hans", "fr", "es", "ja", "ko"]
        var messages: Set<String> = [L10n.text(key)]

        for code in supportedLanguageCodes {
            guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
                  let bundle = Bundle(path: path)
            else {
                continue
            }

            let localized = bundle.localizedString(forKey: key, value: nil, table: nil)
            if localized != key {
                messages.insert(localized)
            }
        }

        return messages
    }

    private static func excludedWarningMessage(for account: AgentAccount) -> String {
        guard let message = account.usageSyncError?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty
        else {
            return L10n.text("sync.excluded.default_message")
        }
        return message
    }

    private static func modeText(for mode: SwitchMode) -> String {
        switch mode {
        case .manual:
            return L10n.text("mode.manual")
        case .intelligent:
            return L10n.text("mode.intelligent")
        case .focus:
            return L10n.text("mode.focus")
        }
    }

    private static func updatedText(since date: Date?, now: Date) -> String {
        guard let date else { return L10n.text("menu_bar.updated.never") }
        return L10n.text("menu_bar.updated.format", durationText(from: date, to: now))
    }

    private static func resetText(for date: Date?, now: Date) -> String {
        guard let date else { return L10n.text("menu_bar.reset.now") }
        return durationText(from: now, to: date)
    }

    private static func durationText(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        if seconds < 60 { return L10n.text("menu_bar.reset.now") }

        let minutes = seconds / 60
        if minutes < 60 { return L10n.text("menu_bar.reset.minutes_format", minutes) }

        let hours = minutes / 60
        if hours < 24 { return L10n.text("menu_bar.reset.hours_format", hours) }

        return L10n.text("menu_bar.reset.days_format", hours / 24)
    }

    private static func percentText(_ ratio: Double) -> String {
        let clampedRatio = max(0, min(1, ratio))
        return "\(Int((clampedRatio * 100).rounded()))%"
    }

    private static func remainingPercent(fromUsagePercent usagePercent: Int?) -> Int? {
        usagePercent.map { max(0, min(100, 100 - $0)) }
    }
}
