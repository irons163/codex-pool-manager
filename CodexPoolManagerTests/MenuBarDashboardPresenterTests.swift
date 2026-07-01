import Foundation
import Testing
@testable import CodexPoolManager

private let menuBarLanguageOverrideMutationLock = NSLock()

private func withMenuBarLanguageOverride(_ languageCode: String, _ body: () throws -> Void) rethrows {
    menuBarLanguageOverrideMutationLock.lock()
    defer { menuBarLanguageOverrideMutationLock.unlock() }

    let defaults = UserDefaults.standard
    let key = L10n.languageOverrideKey
    let previous = defaults.object(forKey: key)
    defer {
        if let previous {
            defaults.set(previous, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    defaults.set(languageCode, forKey: key)
    try body()
}

private func withMenuBarLanguageAndTimeZoneOverride(
    _ languageCode: String,
    timeZone: TimeZone,
    _ body: () throws -> Void
) rethrows {
    menuBarLanguageOverrideMutationLock.lock()
    defer { menuBarLanguageOverrideMutationLock.unlock() }

    let defaults = UserDefaults.standard
    let key = L10n.languageOverrideKey
    let previousLanguage = defaults.object(forKey: key)
    let previousTimeZone = NSTimeZone.default
    defer {
        if let previousLanguage {
            defaults.set(previousLanguage, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        NSTimeZone.default = previousTimeZone
    }

    defaults.set(languageCode, forKey: key)
    NSTimeZone.default = timeZone
    try body()
}

@MainActor
struct MenuBarDashboardPresenterTests {
    private func makeAccount(
        id: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        name: String = "paid@example.com",
        usedUnits: Int = 20,
        quota: Int = 100,
        groupName: String = "Default",
        isPaid: Bool = true,
        planType: String? = nil,
        weeklyResetAt: Date? = Date(timeIntervalSince1970: 1_800),
        fiveHourWindowResetAt: Date? = Date(timeIntervalSince1970: 1_200),
        fiveHourUsedPercent: Int? = 25,
        rateLimitResetCreditsAvailableCount: Int? = nil,
        rateLimitResetCreditsEstimatedExpiresAt: Date? = nil,
        rateLimitResetCreditEstimatedExpiries: [Date] = [],
        usageSyncError: String? = nil,
        isUsageSyncExcluded: Bool = false,
        credentialType: AgentAccountCredentialType = .chatGPTOAuth
    ) -> AgentAccount {
        AgentAccount(
            id: id,
            name: name,
            groupName: groupName,
            usedUnits: usedUnits,
            quota: quota,
            credentialType: credentialType,
            chatGPTAccountID: "user-\(id.uuidString)",
            usageWindowResetAt: weeklyResetAt,
            primaryUsagePercent: fiveHourUsedPercent,
            primaryUsageResetAt: fiveHourWindowResetAt,
            isPaid: isPaid,
            planType: planType,
            rateLimitResetCreditsAvailableCount: rateLimitResetCreditsAvailableCount,
            rateLimitResetCreditsEstimatedExpiresAt: rateLimitResetCreditsEstimatedExpiresAt,
            rateLimitResetCreditEstimatedExpiries: rateLimitResetCreditEstimatedExpiries,
            isUsageSyncExcluded: isUsageSyncExcluded,
            usageSyncError: usageSyncError
        )
    }

    @Test
    func presenterBuildsPaidActiveAccountSummary() {
        let activeID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        var state = AccountPoolState(
            accounts: [
                makeAccount(id: activeID),
                makeAccount(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    name: "backup@example.com",
                    usedUnits: 80,
                    quota: 100,
                    isPaid: false
                )
            ],
            mode: .manual
        )
        state.markActiveAccountForSwitchLaunch(activeID, now: Date(timeIntervalSince1970: 1_010))
        state.markUsageSynced(at: Date(timeIntervalSince1970: 1_000))

        let snapshot = MenuBarDashboardPresenter.makeSnapshot(
            from: state,
            isSyncing: false,
            lastSyncError: nil,
            now: Date(timeIntervalSince1970: 1_030)
        )

        #expect(snapshot.title == "Codex w 80% · 5h 75% · 30s")
        #expect(snapshot.totalAccountsText == "2")
        #expect(snapshot.availableAccountsText == "2")
        #expect(snapshot.modeText == L10n.text("mode.manual"))
        #expect(snapshot.headerSummaryText == "\(L10n.text("menu_bar.header.subtitle")) · \(L10n.text("menu_bar.summary.accounts")) 2 · \(L10n.text("menu_bar.summary.available")) 2 · \(L10n.text("menu_bar.summary.usage")) 50% · \(L10n.text("mode.manual"))")
        #expect(snapshot.activeAccount?.name == "paid@example.com")
        #expect(snapshot.activeAccount?.weeklyRemainingText == "80%")
        #expect(snapshot.activeAccount?.fiveHourRemainingText == "75%")
        #expect(snapshot.activeAccount?.resetText.contains(":") == true)
        #expect(snapshot.activeAccount?.fiveHourResetText?.contains(":") == true)
        #expect(snapshot.accountRows.map(\.name) == ["paid@example.com", "backup@example.com"])
        #expect(snapshot.accountRows.last?.fiveHourRemainingText == nil)
    }

    @Test
    func presenterKeepsAccountGroupsForMenuBarFiltering() {
        let defaultID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let workID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        var state = AccountPoolState(
            accounts: [
                makeAccount(id: defaultID, name: "personal@example.com"),
                makeAccount(id: workID, name: "work@example.com", groupName: "Work")
            ],
            mode: .manual
        )
        state.markActiveAccountForSwitchLaunch(workID, now: Date(timeIntervalSince1970: 1_010))

        let snapshot = MenuBarDashboardPresenter.makeSnapshot(
            from: state,
            isSyncing: false,
            lastSyncError: nil,
            now: Date(timeIntervalSince1970: 1_030),
            accountOrderSettings: MenuBarAccountOrderSettings(
                activeAccountFirst: false,
                paidAccountFirst: false,
                apiKeyAccountLast: false
            )
        )

        #expect(snapshot.accountGroupNames == [AgentAccount.defaultGroupName, "Work"])
        #expect(snapshot.accountRows.map(\.groupName) == [AgentAccount.defaultGroupName, "Work"])
        #expect(snapshot.activeAccount?.groupName == "Work")
    }

    @Test
    func presenterSortsMenuBarAccountsUsingDashboardAccountUsageSettings() {
        let freeID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let relayID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let proID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let activePlusID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        var state = AccountPoolState(
            accounts: [
                makeAccount(id: freeID, name: "free@example.com", isPaid: false),
                makeAccount(id: relayID, name: "relay", isPaid: false, credentialType: .relayAPIKey),
                makeAccount(id: proID, name: "pro@example.com", isPaid: true, planType: "pro"),
                makeAccount(id: activePlusID, name: "plus@example.com", isPaid: true, planType: "plus")
            ],
            mode: .manual
        )
        state.markActiveAccountForSwitchLaunch(activePlusID, now: Date(timeIntervalSince1970: 1_010))

        let snapshot = MenuBarDashboardPresenter.makeSnapshot(
            from: state,
            isSyncing: false,
            lastSyncError: nil,
            now: Date(timeIntervalSince1970: 1_030),
            accountOrderSettings: MenuBarAccountOrderSettings(
                activeAccountFirst: true,
                paidAccountFirst: true,
                apiKeyAccountLast: true
            )
        )

        #expect(snapshot.accountRows.map(\.name) == [
            "plus@example.com",
            "pro@example.com",
            "free@example.com",
            "relay"
        ])
    }

    @Test
    func presenterSurfacesPlanBadgesForMenuBarAccountRows() {
        let plusID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let proID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let relayID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let state = AccountPoolState(
            accounts: [
                makeAccount(id: plusID, name: "plus@example.com", isPaid: true, planType: "plus"),
                makeAccount(id: proID, name: "pro@example.com", isPaid: true, planType: "pro"),
                makeAccount(id: relayID, name: "relay", isPaid: false, credentialType: .relayAPIKey)
            ],
            mode: .manual
        )

        let snapshot = MenuBarDashboardPresenter.makeSnapshot(
            from: state,
            isSyncing: false,
            lastSyncError: nil,
            now: Date(timeIntervalSince1970: 1_030)
        )

        #expect(snapshot.accountRows.first(where: { $0.id == plusID })?.planBadgeText == "Plus")
        #expect(snapshot.accountRows.first(where: { $0.id == proID })?.planBadgeText == "Pro")
        #expect(snapshot.accountRows.first(where: { $0.id == relayID })?.credentialLabel == L10n.text("account.api_key_badge"))
        #expect(snapshot.accountRows.first(where: { $0.id == relayID })?.planBadgeText == nil)
    }

    @Test
    func presenterFormatsEstimatedResetCreditExpiry() throws {
        try withMenuBarLanguageAndTimeZoneOverride(
            "zh-Hant",
            timeZone: try #require(TimeZone(secondsFromGMT: 8 * 60 * 60))
        ) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let firstExpiry = try #require(calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 29,
                hour: 23,
                minute: 15,
                second: 42
            )))
            let secondExpiry = try #require(calendar.date(from: DateComponents(
                year: 2026,
                month: 8,
                day: 5,
                hour: 12,
                minute: 34,
                second: 56
            )))
            let accountID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
            let state = AccountPoolState(
                accounts: [
                    makeAccount(
                        id: accountID,
                        planType: "pro",
                        rateLimitResetCreditsAvailableCount: 2,
                        rateLimitResetCreditsEstimatedExpiresAt: firstExpiry,
                        rateLimitResetCreditEstimatedExpiries: [firstExpiry, secondExpiry]
                    )
                ],
                mode: .manual
            )

            let row = try #require(MenuBarDashboardPresenter.makeSnapshot(
                from: state,
                isSyncing: false,
                lastSyncError: nil,
                now: firstExpiry
            ).accountRows.first)

            #expect(row.resetCreditBadgeText == nil)
            #expect(row.resetCreditDetailText?.components(separatedBy: "\n") == [
                "可重置 2 次",
                "第 1 次期限：2026/7/29 23:15:42 GMT+8",
                "第 2 次期限：2026/8/5 12:34:56 GMT+8"
            ])
            #expect(row.resetCreditNoteText?.components(separatedBy: "\n") == [
                "依前次成功同步時間加 30 天推估，實際期限可能不同。"
            ])
            #expect(row.resetCreditAccessibilityLabel == "可重置 2 次，推估 2026/7/29 23:15:42 GMT+8 到期")
        }
    }

    @Test
    func presenterHidesResetCreditBadgeForRelayAccounts() throws {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        let relayID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let state = AccountPoolState(
            accounts: [
                makeAccount(
                    id: relayID,
                    name: "relay",
                    isPaid: false,
                    rateLimitResetCreditsAvailableCount: 2,
                    rateLimitResetCreditsEstimatedExpiresAt: expiry,
                    credentialType: .relayAPIKey
                )
            ],
            mode: .manual
        )

        let row = try #require(MenuBarDashboardPresenter.makeSnapshot(
            from: state,
            isSyncing: false,
            lastSyncError: nil,
            now: expiry
        ).accountRows.first)

        #expect(row.resetCreditBadgeText == nil)
        #expect(row.resetCreditDetailText == nil)
        #expect(row.resetCreditNoteText == nil)
    }

    @Test
    func resetCreditFormatterBuildsPerCreditDetailLines() throws {
        try withMenuBarLanguageAndTimeZoneOverride(
            "zh-Hant",
            timeZone: try #require(TimeZone(secondsFromGMT: 8 * 60 * 60))
        ) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let firstExpiry = try #require(calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 30,
                hour: 20,
                minute: 3,
                second: 24
            )))
            let secondExpiry = try #require(calendar.date(from: DateComponents(
                year: 2026,
                month: 8,
                day: 1,
                hour: 9,
                minute: 10,
                second: 11
            )))
            let account = makeAccount(
                rateLimitResetCreditsAvailableCount: 2,
                rateLimitResetCreditsEstimatedExpiresAt: firstExpiry,
                rateLimitResetCreditEstimatedExpiries: [firstExpiry, secondExpiry]
            )

            let presentation = try #require(ResetCreditPresentationFormatter.presentation(for: account))

            #expect(presentation.detailLines == [
                "可重置 2 次",
                "第 1 次期限：2026/7/30 20:03:24 GMT+8",
                "第 2 次期限：2026/8/1 09:10:11 GMT+8"
            ])
            #expect(presentation.noteText == "依前次成功同步時間加 30 天推估，實際期限可能不同。")
            #expect(presentation.accessibilityLabel == "可重置 2 次，推估 2026/7/30 20:03:24 GMT+8 到期")
        }
    }

    @Test
    func resetCreditFormatterRepeatsLegacyExpiryWhenPerCreditListIsMissing() throws {
        try withMenuBarLanguageAndTimeZoneOverride(
            "zh-Hant",
            timeZone: try #require(TimeZone(secondsFromGMT: 8 * 60 * 60))
        ) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let expiry = try #require(calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 30,
                hour: 20,
                minute: 3,
                second: 24
            )))
            let account = makeAccount(
                rateLimitResetCreditsAvailableCount: 2,
                rateLimitResetCreditsEstimatedExpiresAt: expiry
            )

            let presentation = try #require(ResetCreditPresentationFormatter.presentation(for: account))

            #expect(presentation.detailLines == [
                "可重置 2 次",
                "第 1 次期限：2026/7/30 20:03:24 GMT+8",
                "第 2 次期限：2026/7/30 20:03:24 GMT+8"
            ])
        }
    }

    @Test
    func resetCreditFormatterHidesUnsupportedOrIncompleteAccounts() {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(ResetCreditPresentationFormatter.presentation(for: makeAccount(
            rateLimitResetCreditsAvailableCount: 0,
            rateLimitResetCreditsEstimatedExpiresAt: expiry
        )) == nil)

        #expect(ResetCreditPresentationFormatter.presentation(for: makeAccount(
            rateLimitResetCreditsAvailableCount: 2,
            credentialType: .relayAPIKey
        )) == nil)

        #expect(ResetCreditPresentationFormatter.presentation(for: makeAccount(
            rateLimitResetCreditsAvailableCount: 2
        )) == nil)
    }

    @Test
    func accountOrderSettingsReadsExplicitFalseValuesFromDashboardDefaults() throws {
        let suiteName = "MenuBarAccountOrderSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(false, forKey: MenuBarAccountOrderSettings.activeAccountFirstKey)
        defaults.set(true, forKey: MenuBarAccountOrderSettings.paidAccountFirstKey)
        defaults.set(false, forKey: MenuBarAccountOrderSettings.apiKeyAccountLastKey)

        let settings = MenuBarAccountOrderSettings.fromDashboardDefaults(defaults)

        #expect(settings.activeAccountFirst == false)
        #expect(settings.paidAccountFirst)
        #expect(settings.apiKeyAccountLast == false)
    }

    @Test
    func presenterUsesCompactTwentyFourHourResetTimes() {
        withMenuBarLanguageOverride("zh-Hant") {
            let activeID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
            var state = AccountPoolState(
                accounts: [
                    makeAccount(
                        id: activeID,
                        weeklyResetAt: Date(timeIntervalSince1970: 1_800),
                        fiveHourWindowResetAt: Date(timeIntervalSince1970: 1_200)
                    )
                ],
                mode: .manual
            )
            state.markActiveAccountForSwitchLaunch(activeID, now: Date(timeIntervalSince1970: 1_010))

            let snapshot = MenuBarDashboardPresenter.makeSnapshot(
                from: state,
                isSyncing: false,
                lastSyncError: nil,
                now: Date(timeIntervalSince1970: 1_030)
            )

            let resetText = snapshot.activeAccount?.resetText ?? ""
            let fiveHourResetText = snapshot.activeAccount?.fiveHourResetText ?? ""

            #expect(resetText.contains("/") == true)
            #expect(fiveHourResetText.contains("/") == true)
            #expect(!resetText.contains("上午"))
            #expect(!resetText.contains("下午"))
            #expect(!resetText.contains("月"))
            #expect(!resetText.contains("日"))
            #expect(!fiveHourResetText.contains("上午"))
            #expect(!fiveHourResetText.contains("下午"))
            #expect(!fiveHourResetText.contains("月"))
            #expect(!fiveHourResetText.contains("日"))
        }
    }

    @Test
    func presenterSurfacesWarningsWithoutCountingRelayAsHardFailure() {
        var state = AccountPoolState(
            accounts: [
                makeAccount(
                    name: "relay",
                    usedUnits: 0,
                    quota: 100,
                    isPaid: false,
                    usageSyncError: AgentAccount.relayUsageSyncUnavailableReason,
                    isUsageSyncExcluded: true,
                    credentialType: .relayAPIKey
                ),
                makeAccount(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    name: "expired@example.com",
                    usedUnits: 90,
                    quota: 100,
                    isPaid: true,
                    usageSyncError: L10n.text("usage.sync.error.oauth_login_expired")
                )
            ],
            mode: .intelligent
        )
        state.evaluate(now: Date(timeIntervalSince1970: 1_000))

        let snapshot = MenuBarDashboardPresenter.makeSnapshot(
            from: state,
            isSyncing: false,
            lastSyncError: "network offline",
            now: Date(timeIntervalSince1970: 1_030)
        )

        #expect(snapshot.warningRows.contains(where: { $0.kind == .relayUsageUnavailable }))
        #expect(snapshot.warningRows.contains(where: { $0.kind == .oauthExpired }))
        #expect(snapshot.warningRows.contains(where: { $0.kind == .syncFailed }))
        #expect(snapshot.totalAccountsText == "2")
        #expect(snapshot.availableAccountsText == "1")
        #expect(snapshot.accountRows.first(where: { $0.name == "relay" })?.credentialLabel == L10n.text("account.api_key_badge"))
    }

    @Test
    func presenterClassifiesRelayAndExcludedWarningsSeparately() {
        let excludedMessage = "Excluded from sync by policy"
        var state = AccountPoolState(
            accounts: [
                makeAccount(
                    name: "relay",
                    usedUnits: 0,
                    quota: 100,
                    isPaid: false,
                    usageSyncError: nil,
                    isUsageSyncExcluded: true,
                    credentialType: .relayAPIKey
                ),
                makeAccount(
                    id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                    name: "excluded@example.com",
                    usedUnits: 10,
                    quota: 100,
                    isPaid: true,
                    usageSyncError: excludedMessage,
                    isUsageSyncExcluded: true
                )
            ],
            mode: .manual
        )
        state.evaluate(now: Date(timeIntervalSince1970: 1_000))

        let snapshot = MenuBarDashboardPresenter.makeSnapshot(
            from: state,
            isSyncing: false,
            lastSyncError: nil,
            now: Date(timeIntervalSince1970: 1_030)
        )

        #expect(snapshot.warningRows.contains(where: { $0.kind == .relayUsageUnavailable }))
        #expect(!snapshot.warningRows.contains(where: { $0.kind == .syncFailed }))

        let excludedWarning = snapshot.warningRows.first(where: { $0.kind == .excluded })
        #expect(excludedWarning?.message == excludedMessage)
    }

    @Test
    func presenterRecognizesPersistedLocalizedOAuthExpiredWarnings() {
        var state = AccountPoolState(
            accounts: [
                makeAccount(
                    name: "expired@example.com",
                    usageSyncError: nonCurrentOAuthExpiredMessage()
                )
            ],
            mode: .manual
        )
        state.evaluate(now: Date(timeIntervalSince1970: 1_000))

        let snapshot = MenuBarDashboardPresenter.makeSnapshot(
            from: state,
            isSyncing: false,
            lastSyncError: nil,
            now: Date(timeIntervalSince1970: 1_030)
        )

        #expect(snapshot.warningRows.contains(where: { $0.kind == .oauthExpired }))
    }

    @Test
    func presenterUsesDefaultMessageForExcludedAccountWithoutError() {
        var state = AccountPoolState(
            accounts: [
                makeAccount(
                    name: "excluded@example.com",
                    usageSyncError: nil,
                    isUsageSyncExcluded: true
                )
            ],
            mode: .manual
        )
        state.evaluate(now: Date(timeIntervalSince1970: 1_000))

        let snapshot = MenuBarDashboardPresenter.makeSnapshot(
            from: state,
            isSyncing: false,
            lastSyncError: "  \n\t  ",
            now: Date(timeIntervalSince1970: 1_030)
        )

        let excludedWarning = snapshot.warningRows.first(where: { $0.kind == .excluded })
        #expect(excludedWarning?.message == L10n.text("sync.excluded.default_message"))
        #expect(!snapshot.warningRows.contains(where: { $0.kind == .syncFailed }))
    }

    private func nonCurrentOAuthExpiredMessage() -> String {
        let key = "usage.sync.error.oauth_login_expired"
        let currentMessage = L10n.text(key)

        for code in ["en", "zh-Hant", "zh-Hans", "fr", "es", "ja", "ko"] {
            guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
                  let bundle = Bundle(path: path)
            else {
                continue
            }

            let localized = bundle.localizedString(forKey: key, value: nil, table: nil)
            if localized != key, localized != currentMessage {
                return localized
            }
        }

        return "登入資訊已過期，請重新登入或重新匯入此帳號。"
    }
}
