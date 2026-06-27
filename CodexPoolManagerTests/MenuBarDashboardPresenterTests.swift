import Foundation
import Testing
@testable import CodexPoolManager

@MainActor
struct MenuBarDashboardPresenterTests {
    private func makeAccount(
        id: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        name: String = "paid@example.com",
        usedUnits: Int = 20,
        quota: Int = 100,
        isPaid: Bool = true,
        weeklyResetAt: Date? = Date(timeIntervalSince1970: 1_800),
        fiveHourWindowResetAt: Date? = Date(timeIntervalSince1970: 1_200),
        fiveHourUsedPercent: Int? = 25,
        usageSyncError: String? = nil,
        isUsageSyncExcluded: Bool = false,
        credentialType: AgentAccountCredentialType = .chatGPTOAuth
    ) -> AgentAccount {
        AgentAccount(
            id: id,
            name: name,
            usedUnits: usedUnits,
            quota: quota,
            credentialType: credentialType,
            chatGPTAccountID: "user-\(id.uuidString)",
            usageWindowResetAt: weeklyResetAt,
            primaryUsagePercent: fiveHourUsedPercent,
            primaryUsageResetAt: fiveHourWindowResetAt,
            isPaid: isPaid,
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
        #expect(snapshot.activeAccount?.name == "paid@example.com")
        #expect(snapshot.activeAccount?.weeklyRemainingText == "80%")
        #expect(snapshot.activeAccount?.fiveHourRemainingText == "75%")
        #expect(snapshot.accountRows.map(\.name) == ["paid@example.com", "backup@example.com"])
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
}
