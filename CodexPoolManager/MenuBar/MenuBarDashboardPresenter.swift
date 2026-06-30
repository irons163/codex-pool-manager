import Foundation

struct MenuBarDashboardSnapshot: Equatable {
    let title: String
    let totalAccountsText: String
    let availableAccountsText: String
    let usageText: String
    let modeText: String
    let headerSummaryText: String
    let updatedText: String
    let activeAccount: MenuBarAccountRow?
    let accountGroupNames: [String]
    let accountRows: [MenuBarAccountRow]
    let warningRows: [MenuBarWarningRow]
    let isSyncing: Bool
    let lastSyncError: String?
}

struct MenuBarAccountOrderSettings: Equatable {
    static let activeAccountFirstKey = "pool_dashboard.account_usage.active_first"
    static let paidAccountFirstKey = "pool_dashboard.account_usage.paid_first"
    static let apiKeyAccountLastKey = "pool_dashboard.account_usage.api_key_last"

    let activeAccountFirst: Bool
    let paidAccountFirst: Bool
    let apiKeyAccountLast: Bool

    static func fromDashboardDefaults(_ defaults: UserDefaults = .standard) -> MenuBarAccountOrderSettings {
        MenuBarAccountOrderSettings(
            activeAccountFirst: bool(
                forKey: activeAccountFirstKey,
                in: defaults,
                defaultValue: true
            ),
            paidAccountFirst: bool(
                forKey: paidAccountFirstKey,
                in: defaults,
                defaultValue: false
            ),
            apiKeyAccountLast: bool(
                forKey: apiKeyAccountLastKey,
                in: defaults,
                defaultValue: true
            )
        )
    }

    private static func bool(forKey key: String, in defaults: UserDefaults, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }
}

struct MenuBarAccountRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let groupName: String
    let isActive: Bool
    let isPaid: Bool
    let credentialLabel: String?
    let planBadgeText: String?
    let resetCreditBadgeText: String?
    let resetCreditDetailText: String?
    let resetCreditNoteText: String?
    let resetCreditAccessibilityLabel: String?
    let weeklyRemainingText: String
    let fiveHourRemainingText: String?
    let resetText: String
    let fiveHourResetText: String?
    let warningText: String?
}

private struct ResetCreditPresentation {
    let detailText: String
    let noteText: String?
    let accessibilityLabel: String
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
        now: Date = Date(),
        accountOrderSettings: MenuBarAccountOrderSettings = .fromDashboardDefaults()
    ) -> MenuBarDashboardSnapshot {
        let orderedAccounts = orderedAccounts(
            state.accounts,
            activeAccountID: state.activeAccountID,
            settings: accountOrderSettings
        )
        let accountRows = orderedAccounts.map { account in
            makeAccountRow(account, activeAccountID: state.activeAccountID)
        }
        let activeAccount = state.activeAccount.flatMap { active in
            accountRows.first(where: { $0.id == active.id })
        }
        let totalAccountsText = String(state.accounts.count)
        let availableAccountsText = String(state.availableAccountsCount)
        let usageText = percentText(1 - state.overallUsageRatio)
        let modeText = modeText(for: state.mode)
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
            totalAccountsText: totalAccountsText,
            availableAccountsText: availableAccountsText,
            usageText: usageText,
            modeText: modeText,
            headerSummaryText: headerSummaryText(
                totalAccountsText: totalAccountsText,
                availableAccountsText: availableAccountsText,
                usageText: usageText,
                modeText: modeText
            ),
            updatedText: updatedText(since: state.lastUsageSyncAt, now: now),
            activeAccount: activeAccount,
            accountGroupNames: accountGroupNames(from: state, accountRows: accountRows),
            accountRows: accountRows,
            warningRows: warningRows(from: state, lastSyncError: lastSyncError),
            isSyncing: isSyncing,
            lastSyncError: lastSyncError
        )
    }

    private static func headerSummaryText(
        totalAccountsText: String,
        availableAccountsText: String,
        usageText: String,
        modeText: String
    ) -> String {
        [
            L10n.text("menu_bar.header.subtitle"),
            "\(L10n.text("menu_bar.summary.accounts")) \(totalAccountsText)",
            "\(L10n.text("menu_bar.summary.available")) \(availableAccountsText)",
            "\(L10n.text("menu_bar.summary.usage")) \(usageText)",
            modeText
        ].joined(separator: " · ")
    }

    private static func makeAccountRow(
        _ account: AgentAccount,
        activeAccountID: UUID?
    ) -> MenuBarAccountRow {
        let resetCredit = resetCreditPresentation(for: account)

        return MenuBarAccountRow(
            id: account.id,
            name: account.name,
            groupName: account.groupName,
            isActive: account.id == activeAccountID,
            isPaid: account.isPaid,
            credentialLabel: account.isRelayAPIKeyAccount ? L10n.text("account.api_key_badge") : nil,
            planBadgeText: account.planBadgeText,
            resetCreditBadgeText: nil,
            resetCreditDetailText: resetCredit?.detailText,
            resetCreditNoteText: resetCredit?.noteText,
            resetCreditAccessibilityLabel: resetCredit?.accessibilityLabel,
            weeklyRemainingText: percentText(account.remainingRatio),
            fiveHourRemainingText: account.isPaid
                ? remainingPercent(fromUsagePercent: account.primaryUsagePercent).map { "\($0)%" }
                : nil,
            resetText: resetText(for: account.usageWindowResetAt),
            fiveHourResetText: account.isPaid ? resetText(for: account.primaryUsageResetAt) : nil,
            warningText: account.usageSyncError
        )
    }

    private static func resetCreditPresentation(for account: AgentAccount) -> ResetCreditPresentation? {
        guard account.supportsCodexUsageSync,
              let count = account.rateLimitResetCreditsAvailableCount,
              count > 0,
              let expiry = account.rateLimitResetCreditsEstimatedExpiresAt
        else {
            return nil
        }

        let fullDate = preciseExpiryText(for: expiry)
        let detailLines = L10n.text("menu_bar.reset_credit.detail_format", count, fullDate)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let visibleDetailText = detailLines.prefix(2).joined(separator: "\n")
        let noteText = detailLines.dropFirst(2).joined(separator: "\n")

        return ResetCreditPresentation(
            detailText: visibleDetailText.isEmpty
                ? L10n.text("menu_bar.reset_credit.detail_format", count, fullDate)
                : visibleDetailText,
            noteText: noteText.isEmpty ? nil : noteText,
            accessibilityLabel: L10n.text("menu_bar.reset_credit.accessibility_format", count, fullDate)
        )
    }

    private static func preciseExpiryText(for expiry: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale()
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy/M/d HH:mm:ss"
        return "\(formatter.string(from: expiry)) \(gmtOffsetText(for: formatter.timeZone, at: expiry))"
    }

    private static func gmtOffsetText(for timeZone: TimeZone, at date: Date) -> String {
        let secondsFromGMT = timeZone.secondsFromGMT(for: date)
        let sign = secondsFromGMT >= 0 ? "+" : "-"
        let absoluteSeconds = abs(secondsFromGMT)
        let hours = absoluteSeconds / 3_600
        let minutes = (absoluteSeconds % 3_600) / 60

        if minutes == 0 {
            return "GMT\(sign)\(hours)"
        }

        return String(format: "GMT%@%d:%02d", sign, hours, minutes)
    }

    private static func orderedAccounts(
        _ accounts: [AgentAccount],
        activeAccountID: UUID?,
        settings: MenuBarAccountOrderSettings
    ) -> [AgentAccount] {
        var ordered = accounts

        if settings.paidAccountFirst {
            ordered = ordered.stablePartitioned { $0.isPaid }
        }

        if settings.apiKeyAccountLast {
            ordered = ordered.stablePartitioned { !$0.isRelayAPIKeyAccount }
        }

        if settings.activeAccountFirst,
           let activeAccountID,
           let activeIndex = ordered.firstIndex(where: { $0.id == activeAccountID }) {
            let activeAccount = ordered.remove(at: activeIndex)
            ordered.insert(activeAccount, at: 0)
        }

        return ordered
    }

    private static func accountGroupNames(
        from state: AccountPoolState,
        accountRows: [MenuBarAccountRow]
    ) -> [String] {
        let rowGroupNames = Set(accountRows.map(\.groupName))
        return state.groups.filter { rowGroupNames.contains($0) }
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

    private static func resetText(for date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = L10n.locale()
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
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
