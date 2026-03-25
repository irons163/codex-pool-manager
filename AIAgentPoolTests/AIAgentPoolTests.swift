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
        state.updateAccount(a, chatGPTAccountID: "acct-a")

        let client = MockCodexUsageClient(
            responseByToken: [
                "token-a": CodexUsage(usedUnits: 250, quota: 1200)
            ]
        )
        let sync = CodexUsageSyncService(client: client)
        try await sync.sync(state: &state, now: Date(timeIntervalSince1970: 10))

        #expect(state.accounts.first(where: { $0.id == a })?.usedUnits == 250)
        #expect(state.accounts.first(where: { $0.id == a })?.quota == 1200)
        #expect(state.accounts.first(where: { $0.id == a })?.usageWindowName == nil)
        #expect(state.accounts.first(where: { $0.id == b })?.usedUnits == 100)
    }

    @Test
    func codexSyncStoresUsageWindowMetadata() async throws {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 0, quota: 1000, apiToken: "token-a")
            ],
            mode: .manual
        )
        state.updateAccount(a, chatGPTAccountID: "acct-a")

        let resetAt = Date(timeIntervalSince1970: 1_700_000_000)
        let client = MockCodexUsageClient(
            responseByToken: [
                "token-a": CodexUsage(
                    usedUnits: 85,
                    quota: 100,
                    usageWindowName: "primary_window",
                    usageWindowResetAt: resetAt
                )
            ]
        )
        let sync = CodexUsageSyncService(client: client)
        try await sync.sync(state: &state, now: Date(timeIntervalSince1970: 10))

        #expect(state.accounts[0].usageWindowName == "primary_window")
        #expect(state.accounts[0].usageWindowResetAt == resetAt)
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
        state.updateAccount(a, chatGPTAccountID: "acct-a")

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
    func codexSyncSkipsAccountWithoutChatGPTAccountID() async throws {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 10, quota: 1000, apiToken: "token-a")
            ],
            mode: .manual
        )

        let client = MockCodexUsageClient(
            responseByToken: [
                "token-a": CodexUsage(usedUnits: 999, quota: 2000)
            ]
        )
        let sync = CodexUsageSyncService(client: client)
        try await sync.sync(state: &state, now: Date(timeIntervalSince1970: 10))

        #expect(state.accounts[0].usedUnits == 10)
        #expect(state.accounts[0].quota == 1000)
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
        state.updateAccount(a, chatGPTAccountID: "acct-a")

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
        if let accountID = state.accounts.first?.id {
            state.updateAccount(accountID, chatGPTAccountID: "acct-a")
        }
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
        if let accountID = state.accounts.first?.id {
            state.updateAccount(accountID, chatGPTAccountID: "acct-a")
        }
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
        state.updateAccount(a, chatGPTAccountID: "acct-a")
        let client = MockCodexUsageClient(
            responseByToken: ["token-a": CodexUsage(usedUnits: 100, quota: 1000)]
        )
        let sync = CodexUsageSyncService(client: client)
        let now = Date(timeIntervalSince1970: 123)

        try await sync.sync(state: &state, now: now)

        #expect(state.lastUsageSyncAt == now)
    }

    @Test
    func openAICodexUsageClientParsesUsedUnitsPayloadAndSendsRequiredHeaders() async throws {
        let responseJSON = """
        {
          "used_units": 42,
          "quota": 400
        }
        """
        let data = Data(responseJSON.utf8)
        let endpoint = try #require(URL(string: "https://chatgpt.com/backend-api/wham/usage?case=units"))
        let capturedRequest = LockedValue<URLRequest?>(nil)
        let session = makeMockedURLSession(
            endpoint: endpoint,
            statusCode: 200,
            data: data,
            requestObserver: { request in
                capturedRequest.withLock { $0 = request }
            }
        )

        let client = OpenAICodexUsageClient(endpoint: endpoint, session: session)
        let usage = try await client.fetchUsage(accessToken: "token-123", accountID: "acct-123")

        #expect(usage.usedUnits == 42)
        #expect(usage.quota == 400)

        let request = try #require(capturedRequest.value)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-123")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct-123")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test
    func openAICodexUsageClientParsesRateLimitPayloadAndCapturesRawJSON() async throws {
        let responseJSON = """
        {
          "user_id": "user-001",
          "account_id": "user-001",
          "email": "philtest@example.com",
          "rate_limit": {
            "primary_window": {
              "used_percent": 11,
              "limit_window_seconds": 604800,
              "reset_after_seconds": 526902,
              "reset_at": 1774885346
            }
          }
        }
        """
        let data = Data(responseJSON.utf8)
        let endpoint = try #require(URL(string: "https://chatgpt.com/backend-api/wham/usage?case=rate_limit"))
        let session = makeMockedURLSession(
            endpoint: endpoint,
            statusCode: 200,
            data: data
        )
        let rawCapture = LockedValue<String?>(nil)

        let client = OpenAICodexUsageClient(
            endpoint: endpoint,
            session: session,
            onRawResponse: { raw in
                rawCapture.withLock { $0 = raw }
            }
        )
        let usage = try await client.fetchUsage(accessToken: "token-abc", accountID: "acct-abc")

        #expect(usage.usedUnits == 11)
        #expect(usage.quota == 100)
        #expect(usage.usageWindowName == "primary_window")
        #expect(usage.accountID == "user-001")
        #expect(usage.accountEmail == "philtest@example.com")
        #expect(usage.usageWindowResetAt == Date(timeIntervalSince1970: 1_774_885_346))
        #expect(rawCapture.value?.contains("\"used_percent\": 11") == true)
    }

    @Test
    func oauthAuthorizeURLContainsRequiredParameters() throws {
        let config = OAuthClientConfiguration(
            issuer: URL(string: "https://auth.example.com")!,
            clientID: "client-123",
            scopes: "openid profile email",
            redirectURI: "aiaagentpool://oauth/callback"
        )
        let request = OAuthAuthorizationRequest(
            state: "test-state",
            codeChallenge: "challenge-abc"
        )

        let url = try OAuthAuthorizationRequestBuilder.makeAuthorizeURL(
            config: config,
            request: request
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(components.path == "/oauth/authorize")
        #expect(items["client_id"] == "client-123")
        #expect(items["redirect_uri"] == "aiaagentpool://oauth/callback")
        #expect(items["scope"] == "openid profile email")
        #expect(items["response_type"] == "code")
        #expect(items["state"] == "test-state")
        #expect(items["code_challenge"] == "challenge-abc")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["id_token_add_organizations"] == "true")
        #expect(items["codex_cli_simplified_flow"] == "true")
        #expect(items["originator"] == "codex_cli_rs")
        #expect(items["allowed_workspace_id"] == nil)
    }

    @Test
    func oauthAuthorizeURLIncludesAllowedWorkspaceIDWhenProvided() throws {
        let config = OAuthClientConfiguration(
            issuer: URL(string: "https://auth.example.com")!,
            clientID: "client-123",
            scopes: "openid profile email",
            redirectURI: "aiaagentpool://oauth/callback",
            originator: "codex_cli_rs",
            forcedWorkspaceID: "ws-001"
        )
        let request = OAuthAuthorizationRequest(
            state: "state-2",
            codeChallenge: "challenge-2"
        )

        let url = try OAuthAuthorizationRequestBuilder.makeAuthorizeURL(
            config: config,
            request: request
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(items["allowed_workspace_id"] == "ws-001")
    }

    @Test
    func oauthCallbackParserExtractsCodeAndState() throws {
        let callbackURL = try #require(
            URL(string: "aiaagentpool://oauth/callback?code=abc123&state=s1")
        )

        let callback = try OAuthCallbackParser.parse(callbackURL: callbackURL)

        #expect(callback.code == "abc123")
        #expect(callback.state == "s1")
    }

    @Test
    func oauthLocalhostCallbackConfigParsesPortAndPath() throws {
        let redirectURI = try #require(URL(string: "http://localhost:1455/auth/callback"))

        let config = try #require(LocalhostOAuthCallbackConfig(redirectURI: redirectURI))

        #expect(config.host == "localhost")
        #expect(config.port == 1455)
        #expect(config.callbackPath == "/auth/callback")
    }

    @Test
    func oauthLocalhostCallbackExtractorParsesCodeAndStateFromRequestLine() throws {
        let config = LocalhostOAuthCallbackConfig(host: "localhost", port: 1455, callbackPath: "/auth/callback")
        let request = "GET /auth/callback?code=abc123&state=s1 HTTP/1.1\r\nHost: localhost:1455\r\n\r\n"

        let callbackURL = try #require(LocalhostOAuthCallbackExtractor.callbackURL(fromRequest: request, config: config))

        #expect(callbackURL.absoluteString == "http://localhost:1455/auth/callback?code=abc123&state=s1")
    }

    @Test
    func oauthIDTokenClaimsParserExtractsSubjectAccountAndEmail() throws {
        let payload = "{\"sub\":\"user-123\",\"account_id\":\"acct-123\",\"email\":\"demo@example.com\"}"
        let payloadData = try #require(payload.data(using: .utf8))
        let encodedPayload = payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "header.\(encodedPayload).sig"

        let claims = try #require(OAuthIDTokenClaimsParser.parse(token))

        #expect(claims.subject == "user-123")
        #expect(claims.accountID == "acct-123")
        #expect(claims.email == "demo@example.com")
    }

    @Test
    func oauthAccountUpsertResolverMatchesByChatGPTAccountID() {
        let existingID = UUID()
        let accounts = [
            AgentAccount(
                id: existingID,
                name: "existing@example.com",
                usedUnits: 10,
                quota: 100,
                apiToken: "old-token",
                chatGPTAccountID: "acct-123"
            )
        ]

        let matched = OAuthAccountUpsertResolver.resolveExistingAccountID(
            in: accounts,
            chatGPTAccountID: "acct-123",
            accessToken: "new-token",
            email: "existing@example.com"
        )

        #expect(matched == existingID)
    }

    @Test
    func oauthAccountUpsertResolverMatchesByAccessTokenWhenAccountIDMissing() {
        let existingID = UUID()
        let accounts = [
            AgentAccount(
                id: existingID,
                name: "existing@example.com",
                usedUnits: 10,
                quota: 100,
                apiToken: "same-token",
                chatGPTAccountID: nil
            )
        ]

        let matched = OAuthAccountUpsertResolver.resolveExistingAccountID(
            in: accounts,
            chatGPTAccountID: nil,
            accessToken: "same-token",
            email: nil
        )

        #expect(matched == existingID)
    }

    @Test
    func oauthAccountUpsertResolverMatchesByEmailNameAsFallback() {
        let existingID = UUID()
        let accounts = [
            AgentAccount(
                id: existingID,
                name: "existing@example.com",
                usedUnits: 10,
                quota: 100,
                apiToken: "other-token",
                chatGPTAccountID: nil
            )
        ]

        let matched = OAuthAccountUpsertResolver.resolveExistingAccountID(
            in: accounts,
            chatGPTAccountID: nil,
            accessToken: "new-token",
            email: "existing@example.com"
        )

        #expect(matched == existingID)
    }

    @Test
    func oauthTokenRequestBodyContainsExpectedFields() {
        let body = OAuthTokenRequestBuilder.authorizationCodeBody(
            clientID: "client-123",
            code: "code-xyz",
            redirectURI: "aiaagentpool://oauth/callback",
            codeVerifier: "verifier-123"
        )
        let form = String(data: body, encoding: .utf8) ?? ""

        #expect(form.contains("grant_type=authorization_code"))
        #expect(form.contains("client_id=client-123"))
        #expect(form.contains("code=code-xyz"))
        #expect(form.contains("redirect_uri=aiaagentpool%3A%2F%2Foauth%2Fcallback"))
        #expect(form.contains("code_verifier=verifier-123"))
    }

    @Test
    func localCodexDiscoveryParsesNestedOAuthAccounts() {
        let json = """
        {
          "profiles": [
            {
              "name": "Phil",
              "email": "phil@example.com",
              "account_id": "acct-phil",
              "access_token": "sk-local-token-111111"
            },
            {
              "session": {
                "display_name": "Teammate",
                "user_email": "team@example.com",
                "account_id": "acct-team",
                "accessToken": "sk-local-token-222222"
              }
            }
          ]
        }
        """

        let data = Data(json.utf8)
        let accounts = LocalCodexAccountDiscovery.parseAccounts(from: data, source: "/tmp/auth.json")

        #expect(accounts.count == 2)
        #expect(accounts[0].displayName == "Phil")
        #expect(accounts[1].email == "team@example.com")
        #expect(accounts[0].chatGPTAccountID == "acct-phil")
    }

    @Test
    func localCodexDiscoveryDeduplicatesSameToken() {
        let json = """
        {
          "items": [
            {
              "name": "A",
              "email": "same@example.com",
              "access_token": "sk-dup-token"
            },
            {
              "name": "B",
              "email": "same@example.com",
              "accessToken": "sk-dup-token"
            }
          ]
        }
        """

        let data = Data(json.utf8)
        let accounts = LocalCodexAccountDiscovery.parseAccounts(from: data, source: "/tmp/auth.json")

        #expect(accounts.count == 1)
    }

    @Test
    func localCodexDiscoveryFindsEmailWhenTokenAndProfileAreInDifferentLevels() {
        let json = """
        {
          "session": {
            "token": "sk-deep-token-123",
            "profile": {
              "email": "deep@example.com",
              "name": "Deep User"
            },
            "account": {
              "account_id": "acct-deep"
            }
          }
        }
        """

        let data = Data(json.utf8)
        let accounts = LocalCodexAccountDiscovery.parseAccounts(from: data, source: "/tmp/auth.json")

        #expect(accounts.count == 1)
        #expect(accounts[0].email == "deep@example.com")
        #expect(accounts[0].displayName == "Deep User")
        #expect(accounts[0].chatGPTAccountID == "acct-deep")
    }

    @Test
    func codexAuthFileSwitcherRewritesKnownFieldsInNestedJSON() throws {
        let json = """
        {
          "session": {
            "access_token": "old-token",
            "profile": {
              "email": "old@example.com"
            },
            "account_id": "old-account"
          }
        }
        """
        let data = Data(json.utf8)
        let rewritten = try CodexAuthFileSwitcher.rewriteAuthJSON(
            data,
            accessToken: "new-token",
            accountID: "new-account",
            email: "new@example.com"
        )
        let object = try #require(JSONSerialization.jsonObject(with: rewritten) as? [String: Any])
        let session = try #require(object["session"] as? [String: Any])
        let profile = try #require(session["profile"] as? [String: Any])

        #expect(session["access_token"] as? String == "new-token")
        #expect(session["account_id"] as? String == "new-account")
        #expect(profile["email"] as? String == "new@example.com")
    }

    @Test
    func codexAuthFileSwitcherAddsFieldsWhenMissing() throws {
        let json = """
        {
          "plan_type": "free"
        }
        """
        let data = Data(json.utf8)
        let rewritten = try CodexAuthFileSwitcher.rewriteAuthJSON(
            data,
            accessToken: "added-token",
            accountID: "added-account",
            email: "added@example.com"
        )
        let object = try #require(JSONSerialization.jsonObject(with: rewritten) as? [String: Any])

        #expect(object["access_token"] as? String == "added-token")
        #expect(object["account_id"] as? String == "added-account")
        #expect(object["email"] as? String == "added@example.com")
    }
}
private struct MockCodexUsageClient: CodexUsageClient {
    let responseByToken: [String: CodexUsage]
    var shouldThrow: Bool = false
    var shouldThrowError: Error?

    func fetchUsage(accessToken: String, accountID: String) async throws -> CodexUsage {
        if let shouldThrowError {
            throw shouldThrowError
        }
        if shouldThrow {
            throw URLError(.badServerResponse)
        }
        return responseByToken[accessToken] ?? CodexUsage(usedUnits: 0, quota: 1000)
    }
}

private func makeMockedURLSession(
    endpoint: URL,
    statusCode: Int,
    data: Data,
    requestObserver: ((URLRequest) -> Void)? = nil
) -> URLSession {
    MockUsageURLProtocol.setMock(
        for: endpoint.absoluteString,
        statusCode: statusCode,
        data: data,
        requestObserver: requestObserver
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockUsageURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class MockUsageURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responseByURL: [String: (statusCode: Int, data: Data)] = [:]
    private static var observerByURL: [String: (URLRequest) -> Void] = [:]

    static func setMock(
        for url: String,
        statusCode: Int,
        data: Data,
        requestObserver: ((URLRequest) -> Void)?
    ) {
        lock.lock()
        defer { lock.unlock() }
        responseByURL[url] = (statusCode: statusCode, data: data)
        observerByURL[url] = requestObserver
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url?.absoluteString else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let responseTuple: (statusCode: Int, data: Data)?
        let observer: ((URLRequest) -> Void)?
        Self.lock.lock()
        responseTuple = Self.responseByURL[url]
        observer = Self.observerByURL[url]
        Self.lock.unlock()

        observer?(request)
        guard let responseTuple else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: responseTuple.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseTuple.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class LockedValue<Value> {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) {
        _value = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func withLock(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&_value)
    }
}

private actor FlakyCodexUsageClient: CodexUsageClient {
    var failuresBeforeSuccess: Int
    let successUsage: CodexUsage
    init(failuresBeforeSuccess: Int, successUsage: CodexUsage) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
        self.successUsage = successUsage
    }

    func fetchUsage(accessToken: String, accountID: String) async throws -> CodexUsage {
        if failuresBeforeSuccess > 0 {
            failuresBeforeSuccess -= 1
            throw URLError(.timedOut)
        }
        return successUsage
    }
}
