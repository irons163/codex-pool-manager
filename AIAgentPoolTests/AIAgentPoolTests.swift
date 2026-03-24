import Foundation
import Testing
@testable import AIAgentPool

struct AIAgentPoolTests {

    @Test
    func intelligentModeSelectsLowerUsageAccount() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 800, quota: 1000),
                AgentAccount(id: b, name: "B", usedUnits: 100, quota: 1000)
            ],
            mode: .intelligent,
            minSwitchInterval: 300
        )

        state.evaluate(now: Date(timeIntervalSince1970: 0))

        #expect(state.activeAccount?.id == b)
    }

    @Test
    func intelligentModeRespectsMinimumSwitchInterval() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 0, quota: 1000),
                AgentAccount(id: b, name: "B", usedUnits: 200, quota: 1000)
            ],
            mode: .intelligent,
            minSwitchInterval: 300
        )

        let start = Date(timeIntervalSince1970: 0)
        state.evaluate(now: start)
        #expect(state.activeAccount?.id == a)

        state.recordUsage(units: 900, now: start.addingTimeInterval(30))
        #expect(state.activeAccount?.id == a)

        state.evaluate(now: start.addingTimeInterval(310))
        #expect(state.activeAccount?.id == b)
    }

    @Test
    func manualModeSticksToSelectedAccount() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 300, quota: 1000),
                AgentAccount(id: b, name: "B", usedUnits: 100, quota: 1000)
            ],
            mode: .manual
        )

        state.selectManualAccount(b, now: Date(timeIntervalSince1970: 10))
        state.evaluate(now: Date(timeIntervalSince1970: 20))

        #expect(state.activeAccount?.id == b)
    }

    @Test
    func focusModeLocksBestAccountUntilModeChanges() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 200, quota: 1000),
                AgentAccount(id: b, name: "B", usedUnits: 100, quota: 1000)
            ],
            mode: .focus
        )

        state.evaluate(now: Date(timeIntervalSince1970: 0))
        #expect(state.activeAccount?.id == b)

        state.recordUsage(units: 850, now: Date(timeIntervalSince1970: 50))
        #expect(state.activeAccount?.id == b)

        state.setMode(.intelligent, now: Date(timeIntervalSince1970: 400))
        #expect(state.activeAccount?.id == a)
    }

    @Test
    func focusModeProvidesLowUsageWarning() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 900, quota: 1000)
            ],
            mode: .focus,
            lowUsageThresholdRatio: 0.15
        )

        state.evaluate(now: Date(timeIntervalSince1970: 0))

        #expect(state.hasLowUsageWarning)
    }

    @Test
    func addAccountInManualModeSelectsFirstCreatedAccount() {
        var state = AccountPoolState(accounts: [], mode: .manual)

        let accountID = state.addAccount(name: "New", quota: 1000, usedUnits: 0, now: Date(timeIntervalSince1970: 0))

        #expect(state.accounts.count == 1)
        #expect(state.manualAccountID == accountID)
        #expect(state.activeAccount?.id == accountID)
    }

    @Test
    func removeActiveAccountFallsBackToRemainingAccount() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 50, quota: 1000),
                AgentAccount(id: b, name: "B", usedUnits: 400, quota: 1000)
            ],
            mode: .manual
        )
        state.selectManualAccount(a, now: Date(timeIntervalSince1970: 10))
        #expect(state.activeAccount?.id == a)

        state.removeAccount(a, now: Date(timeIntervalSince1970: 20))

        #expect(state.accounts.count == 1)
        #expect(state.activeAccount?.id == b)
        #expect(state.manualAccountID == b)
    }

    @Test
    func updateAccountClampsUsedUnitsToQuota() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 100, quota: 1000)
            ],
            mode: .manual
        )

        state.updateAccount(a, quota: 400, usedUnits: 700, now: Date(timeIntervalSince1970: 0))

        #expect(state.accounts[0].quota == 400)
        #expect(state.accounts[0].usedUnits == 400)
    }

    @Test
    func snapshotCanRestoreState() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 250, quota: 1000)
            ],
            mode: .manual
        )
        state.selectManualAccount(a, now: Date(timeIntervalSince1970: 10))
        let snapshot = state.snapshot

        let restored = AccountPoolState(snapshot: snapshot)

        #expect(restored.accounts == state.accounts)
        #expect(restored.mode == state.mode)
        #expect(restored.manualAccountID == state.manualAccountID)
        #expect(restored.activeAccount?.id == state.activeAccount?.id)
        #expect(restored.minSwitchInterval == state.minSwitchInterval)
        #expect(restored.lowUsageThresholdRatio == state.lowUsageThresholdRatio)
        #expect(restored.minUsageRatioDeltaToSwitch == state.minUsageRatioDeltaToSwitch)
    }

    @Test
    func userDefaultsStoreCanSaveAndLoadSnapshot() {
        let suiteName = "AIAgentPoolTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Cannot create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = UserDefaultsAccountPoolStore(defaults: defaults, key: "snapshot")
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let snapshot = AccountPoolSnapshot(
            accounts: [AgentAccount(id: accountID, name: "A", usedUnits: 150, quota: 1000)],
            activities: [],
            mode: .focus,
            activeAccountID: accountID,
            manualAccountID: accountID,
            focusLockedAccountID: accountID,
            minSwitchInterval: 600,
            lowUsageThresholdRatio: 0.2,
            minUsageRatioDeltaToSwitch: 0.1,
            lastSwitchAt: nil
        )

        store.save(snapshot)
        let loaded = store.load()

        #expect(loaded == snapshot)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func updateSwitchSettingsClampsValues() {
        var state = AccountPoolState(
            accounts: [AgentAccount(id: UUID(), name: "A", usedUnits: 10, quota: 1000)],
            mode: .intelligent
        )

        state.updateSwitchSettings(minSwitchInterval: 5, lowUsageThresholdRatio: 2, minUsageRatioDeltaToSwitch: 9)

        #expect(state.minSwitchInterval == 30)
        #expect(state.lowUsageThresholdRatio == 0.9)
        #expect(state.minUsageRatioDeltaToSwitch == 0.5)
    }

    @Test
    func lowUsageAlertPolicyTriggersOnlyOnEnteringLowStateInFocusMode() {
        var policy = LowUsageAlertPolicy()

        let first = policy.shouldTriggerAlert(mode: .focus, hasLowUsageWarning: true)
        let second = policy.shouldTriggerAlert(mode: .focus, hasLowUsageWarning: true)
        let third = policy.shouldTriggerAlert(mode: .focus, hasLowUsageWarning: false)
        let fourth = policy.shouldTriggerAlert(mode: .focus, hasLowUsageWarning: true)

        #expect(first)
        #expect(!second)
        #expect(!third)
        #expect(fourth)
    }

    @Test
    func lowUsageAlertPolicyDoesNotTriggerOutsideFocusMode() {
        var policy = LowUsageAlertPolicy()

        let intelligent = policy.shouldTriggerAlert(mode: .intelligent, hasLowUsageWarning: true)
        let manual = policy.shouldTriggerAlert(mode: .manual, hasLowUsageWarning: true)

        #expect(!intelligent)
        #expect(!manual)
    }

    @Test
    func intelligentModeReportsSwitchCooldownAfterRecentSwitch() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 0, quota: 1000),
                AgentAccount(id: b, name: "B", usedUnits: 200, quota: 1000)
            ],
            mode: .intelligent,
            minSwitchInterval: 300
        )

        state.evaluate(now: Date(timeIntervalSince1970: 0))
        state.recordUsage(units: 900, now: Date(timeIntervalSince1970: 30))

        #expect(!state.canIntelligentSwitch(now: Date(timeIntervalSince1970: 30)))
        #expect(state.intelligentSwitchCooldownRemaining(now: Date(timeIntervalSince1970: 30)) == 270)
    }

    @Test
    func intelligentModeCooldownReachesZeroWhenIntervalElapsed() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 0, quota: 1000),
                AgentAccount(id: b, name: "B", usedUnits: 200, quota: 1000)
            ],
            mode: .intelligent,
            minSwitchInterval: 300
        )

        state.evaluate(now: Date(timeIntervalSince1970: 0))

        #expect(state.canIntelligentSwitch(now: Date(timeIntervalSince1970: 300)))
        #expect(state.intelligentSwitchCooldownRemaining(now: Date(timeIntervalSince1970: 300)) == 0)
    }

    @Test
    func intelligentModeDoesNotSwitchWhenImprovementIsBelowThreshold() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 300, quota: 1000),
                AgentAccount(id: b, name: "B", usedUnits: 280, quota: 1000)
            ],
            mode: .manual
        )
        state.selectManualAccount(a, now: Date(timeIntervalSince1970: 0))
        state.updateSwitchSettings(minUsageRatioDeltaToSwitch: 0.05, now: Date(timeIntervalSince1970: 0))
        state.setMode(.intelligent, now: Date(timeIntervalSince1970: 301))

        #expect(state.activeAccount?.id == a)
    }

    @Test
    func intelligentModeSwitchesWhenImprovementMeetsThreshold() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 300, quota: 1000),
                AgentAccount(id: b, name: "B", usedUnits: 200, quota: 1000)
            ],
            mode: .manual
        )
        state.selectManualAccount(a, now: Date(timeIntervalSince1970: 0))
        state.updateSwitchSettings(minUsageRatioDeltaToSwitch: 0.05, now: Date(timeIntervalSince1970: 0))
        state.setMode(.intelligent, now: Date(timeIntervalSince1970: 301))

        #expect(state.activeAccount?.id == b)
    }

    @Test
    func snapshotDecodingSupportsLegacyPayloadWithoutNewFields() throws {
        let legacyJSON = """
        {
          "accounts": [
            {
              "id": "00000000-0000-0000-0000-0000000000A1",
              "name": "A",
              "usedUnits": 100,
              "quota": 1000
            }
          ],
          "mode": "智能切換",
          "activeAccountID": "00000000-0000-0000-0000-0000000000A1",
          "manualAccountID": "00000000-0000-0000-0000-0000000000A1",
          "focusLockedAccountID": null,
          "minSwitchInterval": 300,
          "lowUsageThresholdRatio": 0.15
        }
        """

        let data = try #require(legacyJSON.data(using: .utf8))
        let snapshot = try JSONDecoder().decode(AccountPoolSnapshot.self, from: data)

        #expect(snapshot.minUsageRatioDeltaToSwitch == 0)
    }

    @Test
    func usageSummaryCalculatesTotalsAndRatio() {
        let state = AccountPoolState(
            accounts: [
                AgentAccount(id: UUID(), name: "A", usedUnits: 200, quota: 1000),
                AgentAccount(id: UUID(), name: "B", usedUnits: 300, quota: 500)
            ],
            mode: .intelligent
        )

        #expect(state.totalUsedUnits == 500)
        #expect(state.totalQuota == 1500)
        #expect(state.overallUsageRatio == 1.0 / 3.0)
    }

    @Test
    func usageSummaryIsZeroWhenNoAccounts() {
        let state = AccountPoolState(accounts: [], mode: .intelligent)

        #expect(state.totalUsedUnits == 0)
        #expect(state.totalQuota == 0)
        #expect(state.overallUsageRatio == 0)
    }

    @Test
    func poolExhaustedStateIsTrueWhenNoAccountHasRemainingUnits() {
        let state = AccountPoolState(
            accounts: [
                AgentAccount(id: UUID(), name: "A", usedUnits: 1000, quota: 1000),
                AgentAccount(id: UUID(), name: "B", usedUnits: 500, quota: 500)
            ],
            mode: .intelligent
        )

        #expect(state.availableAccountsCount == 0)
        #expect(state.isPoolExhausted)
    }

    @Test
    func poolExhaustedStateIsFalseWhenAtLeastOneAccountHasRemainingUnits() {
        let state = AccountPoolState(
            accounts: [
                AgentAccount(id: UUID(), name: "A", usedUnits: 1000, quota: 1000),
                AgentAccount(id: UUID(), name: "B", usedUnits: 300, quota: 500)
            ],
            mode: .intelligent
        )

        #expect(state.availableAccountsCount == 1)
        #expect(!state.isPoolExhausted)
    }

    @Test
    func intelligentCandidateReturnsLowestUsageAvailableAccount() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        let c = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!
        let state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 500, quota: 1000),
                AgentAccount(id: b, name: "B", usedUnits: 300, quota: 1000),
                AgentAccount(id: c, name: "C", usedUnits: 1000, quota: 1000)
            ],
            mode: .intelligent
        )

        #expect(state.intelligentCandidateID == b)
    }

    @Test
    func intelligentCandidateIsNilWhenAllAccountsExhausted() {
        let state = AccountPoolState(
            accounts: [
                AgentAccount(id: UUID(), name: "A", usedUnits: 1000, quota: 1000),
                AgentAccount(id: UUID(), name: "B", usedUnits: 500, quota: 500)
            ],
            mode: .intelligent
        )

        #expect(state.intelligentCandidateID == nil)
    }

    @Test
    func focusLockIsActiveAndMatchesActiveAccountInFocusMode() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 100, quota: 1000),
                AgentAccount(id: b, name: "B", usedUnits: 300, quota: 1000)
            ],
            mode: .focus
        )

        state.evaluate(now: Date(timeIntervalSince1970: 0))

        #expect(state.isFocusLockActive)
        #expect(state.focusLockedID == state.activeAccount?.id)
    }

    @Test
    func focusLockClearsAfterLeavingFocusMode() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 100, quota: 1000),
                AgentAccount(id: b, name: "B", usedUnits: 300, quota: 1000)
            ],
            mode: .focus
        )

        state.evaluate(now: Date(timeIntervalSince1970: 0))
        state.setMode(.intelligent, now: Date(timeIntervalSince1970: 600))

        #expect(!state.isFocusLockActive)
        #expect(state.focusLockedID == nil)
    }

    @Test
    func switchModeDecodingSupportsEnglishLegacyValues() throws {
        let intelligentData = try #require("\"intelligent\"".data(using: .utf8))
        let manualData = try #require("\"manual\"".data(using: .utf8))
        let focusData = try #require("\"focus\"".data(using: .utf8))

        let intelligent = try JSONDecoder().decode(SwitchMode.self, from: intelligentData)
        let manual = try JSONDecoder().decode(SwitchMode.self, from: manualData)
        let focus = try JSONDecoder().decode(SwitchMode.self, from: focusData)

        #expect(intelligent == .intelligent)
        #expect(manual == .manual)
        #expect(focus == .focus)
    }

    @Test
    func intelligentCooldownPersistsAcrossSnapshotRestore() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 0, quota: 1000),
                AgentAccount(id: b, name: "B", usedUnits: 200, quota: 1000)
            ],
            mode: .intelligent,
            minSwitchInterval: 300
        )

        state.evaluate(now: Date(timeIntervalSince1970: 0))
        let snapshot = state.snapshot
        let restored = AccountPoolState(snapshot: snapshot)

        #expect(restored.intelligentSwitchCooldownRemaining(now: Date(timeIntervalSince1970: 100)) == 200)
        #expect(!restored.canIntelligentSwitch(now: Date(timeIntervalSince1970: 100)))
    }

    @Test
    func resetUsageForAccountSetsUsedUnitsToZero() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 450, quota: 1000)
            ],
            mode: .manual
        )

        state.resetUsage(for: a, now: Date(timeIntervalSince1970: 10))

        #expect(state.accounts[0].usedUnits == 0)
    }

    @Test
    func resetAllUsageSetsEveryAccountToZero() {
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: UUID(), name: "A", usedUnits: 450, quota: 1000),
                AgentAccount(id: UUID(), name: "B", usedUnits: 120, quota: 800)
            ],
            mode: .intelligent
        )

        state.resetAllUsage(now: Date(timeIntervalSince1970: 10))

        #expect(state.accounts.allSatisfy { $0.usedUnits == 0 })
        #expect(state.totalUsedUnits == 0)
    }

    @Test
    func switchingAccountCreatesActivityLogEntry() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 500, quota: 1000),
                AgentAccount(id: b, name: "B", usedUnits: 100, quota: 1000)
            ],
            mode: .intelligent
        )

        state.evaluate(now: Date(timeIntervalSince1970: 0))

        #expect(state.activities.count == 1)
        #expect(state.activities[0].message.contains("切換"))
    }

    @Test
    func activitiesPersistAcrossSnapshotRestore() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 200, quota: 1000)
            ],
            mode: .manual
        )

        state.resetUsage(for: a, now: Date(timeIntervalSince1970: 10))
        let snapshot = state.snapshot
        let restored = AccountPoolState(snapshot: snapshot)

        #expect(!restored.activities.isEmpty)
        #expect(restored.activities.contains(where: { $0.message.contains("重設") }))
    }

    @Test
    func clearActivitiesRemovesAllEntries() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 200, quota: 1000)
            ],
            mode: .manual
        )
        state.resetUsage(for: a, now: Date(timeIntervalSince1970: 1))
        #expect(!state.activities.isEmpty)

        state.clearActivities()

        #expect(state.activities.isEmpty)
    }

    @Test
    func activityLogKeepsLatest100Entries() {
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: UUID(), name: "A", usedUnits: 0, quota: 1000),
                AgentAccount(id: UUID(), name: "B", usedUnits: 0, quota: 1000)
            ],
            mode: .manual
        )

        for i in 0..<120 {
            _ = state.addAccount(name: "N\(i)", quota: 1000, now: Date(timeIntervalSince1970: TimeInterval(i)))
        }

        #expect(state.activities.count == 100)
    }

    @Test
    func destructiveActionLatchRequiresSecondConfirmation() {
        var latch = DestructiveActionLatch()

        let first = latch.confirmOrArm()
        let second = latch.confirmOrArm()

        #expect(!first)
        #expect(second)
    }

    @Test
    func destructiveActionLatchResetsAfterConfirmation() {
        var latch = DestructiveActionLatch()

        _ = latch.confirmOrArm()
        _ = latch.confirmOrArm()
        let third = latch.confirmOrArm()

        #expect(!third)
    }

    @Test
    func snapshotCodecCanEncodeAndDecodeRoundTrip() throws {
        let snapshot = AccountPoolSnapshot(
            accounts: [
                AgentAccount(id: UUID(), name: "A", usedUnits: 200, quota: 1000)
            ],
            activities: [
                PoolActivity(id: UUID(), timestamp: Date(timeIntervalSince1970: 1), message: "切換帳號：A")
            ],
            mode: .manual,
            activeAccountID: nil,
            manualAccountID: nil,
            focusLockedAccountID: nil,
            minSwitchInterval: 300,
            lowUsageThresholdRatio: 0.15,
            minUsageRatioDeltaToSwitch: 0.05,
            lastSwitchAt: Date(timeIntervalSince1970: 2)
        )

        let json = try AccountPoolSnapshotCodec.exportJSON(snapshot)
        let decoded = try AccountPoolSnapshotCodec.importJSON(json)

        #expect(decoded == snapshot)
    }

    @Test
    func snapshotCodecThrowsOnInvalidJSON() {
        #expect(throws: Error.self) {
            _ = try AccountPoolSnapshotCodec.importJSON("not-json")
        }
    }

    @Test
    func codexSyncUpdatesAccountsWithApiToken() async throws {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 0, quota: 1000, apiToken: "token-a"),
                AgentAccount(id: b, name: "B", usedUnits: 100, quota: 1000, apiToken: "")
            ],
            mode: .manual
        )

        let client = MockCodexUsageClient(
            responseByToken: [
                "token-a": CodexUsage(usedUnits: 250, quota: 1200)
            ]
        )
        let sync = CodexUsageSyncService(client: client)
        try await sync.sync(state: &state, now: Date(timeIntervalSince1970: 10))

        #expect(state.accounts.first(where: { $0.id == a })?.usedUnits == 250)
        #expect(state.accounts.first(where: { $0.id == a })?.quota == 1200)
        #expect(state.accounts.first(where: { $0.id == b })?.usedUnits == 100)
    }

    @Test
    func codexSyncKeepsStateWhenClientFails() async {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 10, quota: 1000, apiToken: "bad-token")
            ],
            mode: .manual
        )

        let client = MockCodexUsageClient(responseByToken: [:], shouldThrow: true)
        let sync = CodexUsageSyncService(client: client)
        do {
            try await sync.sync(state: &state, now: Date(timeIntervalSince1970: 10))
            Issue.record("Expected sync to throw")
        } catch {
            #expect(state.accounts[0].usedUnits == 10)
        }
    }

    @Test
    func snapshotExportRedactsApiTokensByDefault() throws {
        let token = "sk-test-secret"
        let snapshot = AccountPoolSnapshot(
            accounts: [
                AgentAccount(id: UUID(), name: "A", usedUnits: 10, quota: 1000, apiToken: token)
            ],
            activities: [],
            mode: .manual,
            activeAccountID: nil,
            manualAccountID: nil,
            focusLockedAccountID: nil,
            minSwitchInterval: 300,
            lowUsageThresholdRatio: 0.15,
            minUsageRatioDeltaToSwitch: 0,
            lastSwitchAt: nil
        )

        let json = try AccountPoolSnapshotCodec.exportJSON(snapshot)

        #expect(!json.contains(token))
    }

    @Test
    func userDefaultsStoreKeepsTokensOutOfSnapshotPayload() throws {
        let suiteName = "AIAgentPoolTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Cannot create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        let vault = InMemoryAccountTokenVault()
        let store = UserDefaultsAccountPoolStore(defaults: defaults, key: "snapshot", tokenVault: vault)

        let token = "sk-live-secret"
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let snapshot = AccountPoolSnapshot(
            accounts: [AgentAccount(id: accountID, name: "A", usedUnits: 10, quota: 1000, apiToken: token)],
            activities: [],
            mode: .manual,
            activeAccountID: nil,
            manualAccountID: nil,
            focusLockedAccountID: nil,
            minSwitchInterval: 300,
            lowUsageThresholdRatio: 0.15,
            minUsageRatioDeltaToSwitch: 0,
            lastSwitchAt: nil
        )

        store.save(snapshot)
        let rawData = try #require(defaults.data(forKey: "snapshot"))
        let rawJSON = String(data: rawData, encoding: .utf8) ?? ""

        #expect(!rawJSON.contains(token))

        let loaded = try #require(store.load())
        #expect(loaded.accounts.first?.apiToken == token)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func codexSyncRetriesAfterTransientFailure() async throws {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 0, quota: 1000, apiToken: "token-a")
            ],
            mode: .manual
        )

        let client = FlakyCodexUsageClient(
            failuresBeforeSuccess: 1,
            successUsage: CodexUsage(usedUnits: 333, quota: 1000)
        )
        let sync = CodexUsageSyncService(client: client, maxRetries: 1)
        try await sync.sync(state: &state, now: Date(timeIntervalSince1970: 10))

        #expect(state.accounts[0].usedUnits == 333)
    }

    @Test
    func codexSyncMapsUnauthorizedError() async {
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: UUID(), name: "A", usedUnits: 0, quota: 1000, apiToken: "token-a")
            ],
            mode: .manual
        )
        let client = MockCodexUsageClient(
            responseByToken: [:],
            shouldThrowError: CodexClientHTTPError(statusCode: 401)
        )
        let sync = CodexUsageSyncService(client: client)

        do {
            try await sync.sync(state: &state)
            Issue.record("Expected unauthorized error")
        } catch let error as CodexSyncError {
            #expect(error == .unauthorized)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func codexSyncMapsRateLimitError() async {
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: UUID(), name: "A", usedUnits: 0, quota: 1000, apiToken: "token-a")
            ],
            mode: .manual
        )
        let client = MockCodexUsageClient(
            responseByToken: [:],
            shouldThrowError: CodexClientHTTPError(statusCode: 429)
        )
        let sync = CodexUsageSyncService(client: client)

        do {
            try await sync.sync(state: &state)
            Issue.record("Expected rate limit error")
        } catch let error as CodexSyncError {
            #expect(error == .rateLimited)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func codexSyncRecordsLastSyncTimestampOnSuccess() async throws {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 0, quota: 1000, apiToken: "token-a")
            ],
            mode: .manual
        )
        let client = MockCodexUsageClient(
            responseByToken: ["token-a": CodexUsage(usedUnits: 100, quota: 1000)]
        )
        let sync = CodexUsageSyncService(client: client)
        let now = Date(timeIntervalSince1970: 123)

        try await sync.sync(state: &state, now: now)

        #expect(state.lastUsageSyncAt == now)
    }
}
private struct MockCodexUsageClient: CodexUsageClient {
    let responseByToken: [String: CodexUsage]
    var shouldThrow: Bool = false
    var shouldThrowError: Error?

    func fetchUsage(apiToken: String) async throws -> CodexUsage {
        if let shouldThrowError {
            throw shouldThrowError
        }
        if shouldThrow {
            throw URLError(.badServerResponse)
        }
        return responseByToken[apiToken] ?? CodexUsage(usedUnits: 0, quota: 1000)
    }
}

private actor FlakyCodexUsageClient: CodexUsageClient {
    var failuresBeforeSuccess: Int
    let successUsage: CodexUsage
    init(failuresBeforeSuccess: Int, successUsage: CodexUsage) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
        self.successUsage = successUsage
    }

    func fetchUsage(apiToken: String) async throws -> CodexUsage {
        if failuresBeforeSuccess > 0 {
            failuresBeforeSuccess -= 1
            throw URLError(.timedOut)
        }
        return successUsage
    }
}
