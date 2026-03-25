import Foundation
import SwiftUI
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
    func snapshotExportOmitsUsageFieldsForRefetchableAccounts() throws {
        let snapshot = AccountPoolSnapshot(
            accounts: [
                AgentAccount(
                    id: UUID(),
                    name: "refetch@example.com",
                    usedUnits: 88,
                    quota: 777,
                    apiToken: "token-refetch",
                    chatGPTAccountID: "acct-refetch",
                    usageWindowName: "primary_window",
                    usageWindowResetAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            ],
            activities: [],
            mode: .intelligent,
            activeAccountID: nil,
            manualAccountID: nil,
            focusLockedAccountID: nil,
            minSwitchInterval: 300,
            lowUsageThresholdRatio: 0.15,
            minUsageRatioDeltaToSwitch: 0.05,
            lastSwitchAt: nil,
            lastUsageSyncAt: nil
        )

        let json = try AccountPoolSnapshotCodec.exportJSON(snapshot, redactSensitive: false)

        #expect(!json.contains("\"usedUnits\""))
        #expect(!json.contains("\"quota\""))
        #expect(!json.contains("\"usageWindowName\""))
        #expect(!json.contains("\"usageWindowResetAt\""))
    }

    @Test
    func snapshotImportResetsUsageForAccountsThatCanRefetch() throws {
        let accountID = UUID()
        let snapshot = AccountPoolSnapshot(
            accounts: [
                AgentAccount(
                    id: accountID,
                    name: "refetch@example.com",
                    usedUnits: 77,
                    quota: 999,
                    apiToken: "token-refetch",
                    chatGPTAccountID: "acct-refetch",
                    usageWindowName: "primary_window",
                    usageWindowResetAt: Date(timeIntervalSince1970: 1_700_000_000)
                ),
                AgentAccount(
                    id: UUID(),
                    name: "manual",
                    usedUnits: 20,
                    quota: 300,
                    apiToken: "",
                    chatGPTAccountID: nil
                )
            ],
            activities: [],
            mode: .manual,
            activeAccountID: nil,
            manualAccountID: nil,
            focusLockedAccountID: nil,
            minSwitchInterval: 300,
            lowUsageThresholdRatio: 0.15,
            minUsageRatioDeltaToSwitch: 0.05,
            lastSwitchAt: nil,
            lastUsageSyncAt: nil
        )

        let normalized = AccountPoolSnapshotCodec.prepareForUsageRefetch(snapshot)

        #expect(normalized.accounts[0].usedUnits == 0)
        #expect(normalized.accounts[0].quota == 100)
        #expect(normalized.accounts[0].usageWindowName == nil)
        #expect(normalized.accounts[0].usageWindowResetAt == nil)
        #expect(normalized.accounts[1].usedUnits == 20)
        #expect(normalized.accounts[1].quota == 300)
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
    func snapshotExportCanIncludeApiTokenForRefetchExport() throws {
        let token = "sk-test-secret"
        let accountID = "acct-refetch"
        let snapshot = AccountPoolSnapshot(
            accounts: [
                AgentAccount(
                    id: UUID(),
                    name: "A",
                    usedUnits: 10,
                    quota: 1000,
                    apiToken: token,
                    chatGPTAccountID: accountID
                )
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

        let json = try AccountPoolSnapshotCodec.exportJSON(snapshot, redactSensitive: false)

        #expect(json.contains(token))
        #expect(json.contains(accountID))
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
    func snapshotExportKeepsUsageFieldsForNonRefetchableAccounts() throws {
        let snapshot = AccountPoolSnapshot(
            accounts: [
                AgentAccount(
                    id: UUID(),
                    name: "local-only",
                    usedUnits: 12,
                    quota: 345,
                    apiToken: "",
                    chatGPTAccountID: nil
                )
            ],
            activities: [],
            mode: .manual,
            activeAccountID: nil,
            manualAccountID: nil,
            focusLockedAccountID: nil,
            minSwitchInterval: 300,
            lowUsageThresholdRatio: 0.15,
            minUsageRatioDeltaToSwitch: 0,
            lastSwitchAt: nil,
            lastUsageSyncAt: nil
        )

        let json = try AccountPoolSnapshotCodec.exportJSON(snapshot, redactSensitive: false)

        #expect(json.contains("\"usedUnits\""))
        #expect(json.contains("\"quota\""))
    }

    @Test
    func snapshotImportJSONSupportsMissingUsageFieldsWithDefaults() throws {
        let json = """
        {
          "accounts": [
            {
              "id": "00000000-0000-0000-0000-0000000000A1",
              "name": "imported",
              "apiToken": "token-a",
              "chatGPTAccountID": "acct-a"
            }
          ],
          "activities": [],
          "mode": "手動切換",
          "activeAccountID": null,
          "manualAccountID": null,
          "focusLockedAccountID": null,
          "minSwitchInterval": 300,
          "lowUsageThresholdRatio": 0.15,
          "minUsageRatioDeltaToSwitch": 0,
          "lastSwitchAt": null,
          "lastUsageSyncAt": null
        }
        """

        let snapshot = try AccountPoolSnapshotCodec.importJSON(json)
        let account = try #require(snapshot.accounts.first)

        #expect(account.usedUnits == 0)
        #expect(account.quota == 100)
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

    @Test
    func codexAuthFileSwitcherThrowsOnInvalidJSON() {
        let invalidData = Data("not-json".utf8)

        #expect(throws: CodexAuthFileSwitcher.SwitchError.invalidJSON) {
            _ = try CodexAuthFileSwitcher.rewriteAuthJSON(
                invalidData,
                accessToken: "token",
                accountID: "account",
                email: "user@example.com"
            )
        }
    }

    @Test
    func codexAuthFileSwitcherDoesNotAddEmailWhenInputEmailIsEmpty() throws {
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
            email: ""
        )
        let object = try #require(JSONSerialization.jsonObject(with: rewritten) as? [String: Any])

        #expect(object["access_token"] as? String == "added-token")
        #expect(object["account_id"] as? String == "added-account")
        #expect(object["email"] == nil)
    }

    @Test
    func localCodexDiscoveryReturnsEmptyForInvalidJSON() {
        let data = Data("not-json".utf8)
        let accounts = LocalCodexAccountDiscovery.parseAccounts(from: data, source: "/tmp/auth.json")

        #expect(accounts.isEmpty)
    }

    @Test
    func localCodexDiscoveryIgnoresPlainTokenWithoutAccessTokenKey() {
        let json = """
        {
          "session": {
            "token": "plain-token",
            "email": "user@example.com"
          }
        }
        """
        let data = Data(json.utf8)
        let accounts = LocalCodexAccountDiscovery.parseAccounts(from: data, source: "/tmp/auth.json")

        #expect(accounts.isEmpty)
    }

    @Test
    func localCodexDiscoveryAcceptsAccessTokenEvenWithoutSkPrefix() {
        let json = """
        {
          "session": {
            "access_token": "non-sk-token",
            "email": "user@example.com",
            "account_id": "acct-1"
          }
        }
        """
        let data = Data(json.utf8)
        let accounts = LocalCodexAccountDiscovery.parseAccounts(from: data, source: "/tmp/auth.json")

        #expect(accounts.count == 1)
        #expect(accounts[0].accessToken == "non-sk-token")
        #expect(accounts[0].email == "user@example.com")
    }

    @Test
    func localCodexOAuthAccountMaskedTokenHandlesShortAndLongToken() {
        let short = LocalCodexOAuthAccount(
            id: "1",
            displayName: "A",
            email: nil,
            source: "test",
            accessToken: "short",
            chatGPTAccountID: nil
        )
        let long = LocalCodexOAuthAccount(
            id: "2",
            displayName: "B",
            email: nil,
            source: "test",
            accessToken: "sk-abcdefghijklmnopqrstuvwxyz",
            chatGPTAccountID: nil
        )

        #expect(short.maskedToken == "********")
        #expect(long.maskedToken.hasPrefix("sk-abc"))
        #expect(long.maskedToken.hasSuffix("wxyz"))
        #expect(long.maskedToken.contains("..."))
    }

    @Test
    func userDefaultsStoreLoadReturnsNilForCorruptedSnapshotData() {
        let suiteName = "AIAgentPoolTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Cannot create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(Data("not-json".utf8), forKey: "snapshot")
        let store = UserDefaultsAccountPoolStore(
            defaults: defaults,
            key: "snapshot",
            tokenVault: InMemoryAccountTokenVault()
        )

        let loaded = store.load()
        #expect(loaded == nil)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test
    func userDefaultsStoreSaveRemovesTokenWhenAccountTokenIsEmpty() throws {
        let suiteName = "AIAgentPoolTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Cannot create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        let vault = InMemoryAccountTokenVault()
        let accountID = UUID()
        vault.setToken("existing-token", for: accountID)

        let store = UserDefaultsAccountPoolStore(defaults: defaults, key: "snapshot", tokenVault: vault)
        let snapshot = AccountPoolSnapshot(
            accounts: [
                AgentAccount(
                    id: accountID,
                    name: "A",
                    usedUnits: 10,
                    quota: 100,
                    apiToken: "",
                    chatGPTAccountID: "acct-1"
                )
            ],
            activities: [],
            mode: .manual,
            activeAccountID: accountID,
            manualAccountID: accountID,
            focusLockedAccountID: nil,
            minSwitchInterval: 300,
            lowUsageThresholdRatio: 0.15,
            minUsageRatioDeltaToSwitch: 0,
            lastSwitchAt: nil
        )

        store.save(snapshot)

        #expect(vault.token(for: accountID) == nil)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

extension AIAgentPoolTests {

    @Test
    func poolDashboardBackupCoordinatorExportSnapshotRedactsToken() throws {
        let coordinator = PoolDashboardBackupCoordinator()
        let accountID = UUID()
        let snapshot = AccountPoolSnapshot(
            accounts: [
                AgentAccount(
                    id: accountID,
                    name: "Redact Me",
                    usedUnits: 44,
                    quota: 100,
                    apiToken: "token-secret",
                    chatGPTAccountID: "acct-1"
                )
            ],
            activities: [],
            mode: .manual,
            activeAccountID: accountID,
            manualAccountID: accountID,
            focusLockedAccountID: nil,
            minSwitchInterval: 300,
            lowUsageThresholdRatio: 0.15,
            minUsageRatioDeltaToSwitch: 0,
            lastSwitchAt: nil
        )

        let exported = try #require(coordinator.exportSnapshot(from: snapshot).json)
        let object = try #require(JSONSerialization.jsonObject(with: Data(exported.utf8)) as? [String: Any])
        let accounts = try #require(object["accounts"] as? [[String: Any]])
        let first = try #require(accounts.first)

        #expect(first["apiToken"] as? String == "")
        #expect(first["quota"] as? Int == 100)
        #expect(first["usedUnits"] as? Int == 44)
    }

    @Test
    func poolDashboardBackupCoordinatorExportRefetchableKeepsTokenAndDropsUsageFields() throws {
        let coordinator = PoolDashboardBackupCoordinator()
        let accountID = UUID()
        let snapshot = AccountPoolSnapshot(
            accounts: [
                AgentAccount(
                    id: accountID,
                    name: "Refetch",
                    usedUnits: 88,
                    quota: 100,
                    apiToken: "token-keep",
                    chatGPTAccountID: "acct-2",
                    usageWindowName: "primary_window",
                    usageWindowResetAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            ],
            activities: [],
            mode: .manual,
            activeAccountID: accountID,
            manualAccountID: accountID,
            focusLockedAccountID: nil,
            minSwitchInterval: 300,
            lowUsageThresholdRatio: 0.15,
            minUsageRatioDeltaToSwitch: 0,
            lastSwitchAt: nil
        )

        let exported = try #require(coordinator.exportRefetchableSnapshot(from: snapshot).json)
        let object = try #require(JSONSerialization.jsonObject(with: Data(exported.utf8)) as? [String: Any])
        let accounts = try #require(object["accounts"] as? [[String: Any]])
        let first = try #require(accounts.first)

        #expect(first["apiToken"] as? String == "token-keep")
        #expect(first["quota"] == nil)
        #expect(first["usedUnits"] == nil)
        #expect(first["usageWindowName"] == nil)
        #expect(first["usageWindowResetAt"] == nil)
    }

    @Test
    func poolDashboardBackupCoordinatorImportNormalizesRefetchableUsage() throws {
        let coordinator = PoolDashboardBackupCoordinator()
        let accountID = UUID()
        let snapshot = AccountPoolSnapshot(
            accounts: [
                AgentAccount(
                    id: accountID,
                    name: "Import",
                    usedUnits: 99,
                    quota: 1000,
                    apiToken: "token-import",
                    chatGPTAccountID: "acct-import",
                    usageWindowName: "primary_window",
                    usageWindowResetAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            ],
            activities: [],
            mode: .manual,
            activeAccountID: accountID,
            manualAccountID: accountID,
            focusLockedAccountID: nil,
            minSwitchInterval: 300,
            lowUsageThresholdRatio: 0.15,
            minUsageRatioDeltaToSwitch: 0,
            lastSwitchAt: nil
        )
        let json = try AccountPoolSnapshotCodec.exportJSON(snapshot, redactSensitive: false)

        let importedState = try #require(coordinator.importSnapshotState(from: json).state)
        let importedAccount = try #require(importedState.accounts.first)

        #expect(importedAccount.usedUnits == 0)
        #expect(importedAccount.quota == 100)
        #expect(importedAccount.apiToken == "token-import")
        #expect(importedAccount.chatGPTAccountID == "acct-import")
        #expect(importedAccount.usageWindowName == nil)
    }

    @Test
    func poolAccountUsagePresenterLabelsForPercentUsageAccount() {
        let presenter = PoolAccountUsagePresenter()
        let account = AgentAccount(
            id: UUID(),
            name: "Percent",
            usedUnits: 11,
            quota: 100,
            apiToken: "token",
            chatGPTAccountID: "acct-1"
        )

        #expect(presenter.isPercentUsageAccount(account))
        #expect(presenter.usageSourceLabel(for: account) == "用量來源：response.rate_limit.primary_window.used_percent")
        #expect(presenter.remainingLabel(for: account) == "剩餘 89%")
    }

    @Test
    func poolAccountUsagePresenterLabelsForLocalAccount() {
        let presenter = PoolAccountUsagePresenter()
        let account = AgentAccount(
            id: UUID(),
            name: "Local",
            usedUnits: 12,
            quota: 1000,
            apiToken: "",
            chatGPTAccountID: nil
        )

        #expect(!presenter.isPercentUsageAccount(account))
        #expect(presenter.usageSourceLabel(for: account) == "用量來源：手動/本地設定")
        #expect(presenter.usageWindowDetailLabel(for: account) == nil)
        #expect(presenter.remainingLabel(for: account) == "剩餘 988")
    }

    @Test
    func poolAccountUsagePresenterBuildsUsageWindowDetail() {
        let presenter = PoolAccountUsagePresenter()
        let account = AgentAccount(
            id: UUID(),
            name: "Window",
            usedUnits: 20,
            quota: 100,
            apiToken: "token",
            chatGPTAccountID: "acct",
            usageWindowName: "primary_window",
            usageWindowResetAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let label = presenter.usageWindowDetailLabel(for: account)

        #expect(label?.contains("視窗：primary_window") == true)
        #expect(label?.contains("重置：") == true)
    }

    @Test
    func poolDashboardAccountBindingAdapterUpdatesNameAndQuotaAndUsed() {
        let id = UUID()
        var state = AccountPoolState(
            accounts: [AgentAccount(id: id, name: "Old", usedUnits: 10, quota: 100)],
            mode: .manual
        )
        let binding = Binding<AccountPoolState>(
            get: { state },
            set: { state = $0 }
        )
        let adapter = PoolDashboardAccountBindingAdapter(state: binding)

        adapter.nameBinding(for: id).wrappedValue = "New"
        adapter.quotaBinding(for: id).wrappedValue = 200
        adapter.usedBinding(for: id).wrappedValue = 25

        #expect(state.accounts.first?.name == "New")
        #expect(state.accounts.first?.quota == 200)
        #expect(state.accounts.first?.usedUnits == 25)
    }

    @Test
    func poolDashboardAccountBindingAdapterReturnsDefaultsForMissingAccount() {
        var state = AccountPoolState(accounts: [], mode: .manual)
        let binding = Binding<AccountPoolState>(
            get: { state },
            set: { state = $0 }
        )
        let adapter = PoolDashboardAccountBindingAdapter(state: binding)
        let unknownID = UUID()

        #expect(adapter.nameBinding(for: unknownID).wrappedValue == "")
        #expect(adapter.quotaBinding(for: unknownID).wrappedValue == 100)
        #expect(adapter.usedBinding(for: unknownID).wrappedValue == 0)
    }

    @Test
    func poolDashboardStrategyBindingAdapterUpdatesStateViaBindings() {
        let id = UUID()
        var state = AccountPoolState(
            accounts: [AgentAccount(id: id, name: "A", usedUnits: 0, quota: 100)],
            mode: .manual,
            minSwitchInterval: 300,
            lowUsageThresholdRatio: 0.15,
            minUsageRatioDeltaToSwitch: 0.05
        )
        let binding = Binding<AccountPoolState>(
            get: { state },
            set: { state = $0 }
        )
        let adapter = PoolDashboardStrategyBindingAdapter(state: binding)

        adapter.mode.wrappedValue = .focus
        adapter.manualSelection.wrappedValue = id
        adapter.minSwitchInterval.wrappedValue = 420
        adapter.lowThreshold.wrappedValue = 0.2
        adapter.minUsageDelta.wrappedValue = 0.1

        #expect(state.mode == .focus)
        #expect(state.manualAccountID == id)
        #expect(state.minSwitchInterval == 420)
        #expect(state.lowUsageThresholdRatio == 0.2)
        #expect(state.minUsageRatioDeltaToSwitch == 0.1)
    }

    @Test
    func poolDashboardStrategyBindingAdapterManualSelectionFallsBackToFirstAccount() {
        let firstID = UUID()
        var state = AccountPoolState(
            accounts: [AgentAccount(id: firstID, name: "First", usedUnits: 0, quota: 100)],
            mode: .manual
        )
        let binding = Binding<AccountPoolState>(
            get: { state },
            set: { state = $0 }
        )
        let adapter = PoolDashboardStrategyBindingAdapter(state: binding)

        #expect(adapter.manualSelection.wrappedValue == firstID)
    }

    @Test
    func poolDashboardBackupCoordinatorImportSnapshotStateReturnsFailureOnInvalidJSON() {
        let coordinator = PoolDashboardBackupCoordinator()

        let result = coordinator.importSnapshotState(from: "{invalid-json")

        #expect(result.state == nil)
        #expect(result.errorMessage?.hasPrefix("匯入失敗：") == true)
    }

    @Test
    func poolAccountUsagePresenterProgressColorThresholds() {
        let presenter = PoolAccountUsagePresenter()
        let low = AgentAccount(id: UUID(), name: "Low", usedUnits: 10, quota: 100)
        let medium = AgentAccount(id: UUID(), name: "Medium", usedUnits: 75, quota: 100)
        let high = AgentAccount(id: UUID(), name: "High", usedUnits: 95, quota: 100)

        #expect(presenter.usageProgressColor(for: low) == .blue)
        #expect(presenter.usageProgressColor(for: medium) == .orange)
        #expect(presenter.usageProgressColor(for: high) == .red)
    }

    @Test
    func poolDashboardSwitchLaunchCoordinatorReturnsErrorWhenAccountHasNoToken() async {
        let coordinator = PoolDashboardSwitchLaunchCoordinator()
        let account = AgentAccount(
            id: UUID(),
            name: "NoToken",
            usedUnits: 0,
            quota: 100,
            apiToken: "",
            chatGPTAccountID: "acct-1"
        )

        let output = await coordinator.switchAndLaunch(
            account: account,
            currentAuthorizedAuthFileURL: nil,
            authFileAccessService: CodexAuthFileAccessService(bookmarkKey: "test_no_token"),
            authorizeAuthFile: { nil }
        )

        #expect(output.errorMessage == "此帳號沒有可用 token，無法切換")
        #expect(output.switchLaunchLog.contains("失敗：沒有 token"))
    }

    @Test
    func poolDashboardSwitchLaunchCoordinatorReturnsErrorWhenAccountMissingAccountID() async {
        let coordinator = PoolDashboardSwitchLaunchCoordinator()
        let account = AgentAccount(
            id: UUID(),
            name: "NoAccountID",
            usedUnits: 0,
            quota: 100,
            apiToken: "token-ok",
            chatGPTAccountID: nil
        )

        let output = await coordinator.switchAndLaunch(
            account: account,
            currentAuthorizedAuthFileURL: nil,
            authFileAccessService: CodexAuthFileAccessService(bookmarkKey: "test_no_account_id"),
            authorizeAuthFile: { nil }
        )

        #expect(output.errorMessage == "此帳號缺少 Account ID，無法切換")
        #expect(output.switchLaunchLog.contains("失敗：沒有 account_id"))
    }

    @Test
    func poolDashboardRuntimeCoordinatorOAuthReturnsErrorForInvalidIssuer() async {
        let coordinator = PoolDashboardRuntimeCoordinator()
        let state = AccountPoolState(accounts: [], mode: .manual)

        let output = await coordinator.signInWithOAuth(
            from: state,
            input: .init(
                issuer: "not-a-valid-url",
                clientID: "client",
                scopes: "openid profile email",
                redirectURI: "http://localhost:1455/auth/callback",
                originator: "codex_cli_rs",
                workspaceID: "",
                accountNameInput: "Name",
                fallbackQuota: 1000
            )
        )

        #expect(output.state.accounts.isEmpty)
        #expect(output.oauthSuccessMessage == nil)
        #expect(output.oauthError != nil)
        #expect(output.nextOAuthAccountName == "Name")
        #expect(output.shouldRefreshLocalOAuthAccounts == false)
    }
}

extension AIAgentPoolTests {

    @Test
    func poolDashboardLifecycleCoordinatorOnAppearPrimesLowUsageAlertState() {
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: UUID(), name: "A", usedUnits: 95, quota: 100)
            ],
            mode: .focus,
            lowUsageThresholdRatio: 0.15
        )
        var policy = LowUsageAlertPolicy()
        let coordinator = PoolDashboardLifecycleCoordinator()

        coordinator.onAppear(state: &state, lowUsageAlertPolicy: &policy)

        let shouldShowImmediately = coordinator.shouldShowLowUsageAlert(
            state: state,
            lowUsageAlertPolicy: &policy
        )
        #expect(!shouldShowImmediately)
    }

    @Test
    func poolDashboardLifecycleCoordinatorShowsAlertOnTransitionToLowUsage() {
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: UUID(), name: "A", usedUnits: 10, quota: 100)
            ],
            mode: .focus,
            lowUsageThresholdRatio: 0.15
        )
        var policy = LowUsageAlertPolicy()
        let coordinator = PoolDashboardLifecycleCoordinator()

        coordinator.onAppear(state: &state, lowUsageAlertPolicy: &policy)
        state.updateAccount(state.accounts[0].id, usedUnits: 95)
        state.evaluate()

        let shouldShow = coordinator.shouldShowLowUsageAlert(
            state: state,
            lowUsageAlertPolicy: &policy
        )
        #expect(shouldShow)
    }

    @Test
    func poolDashboardLifecycleFlowCoordinatorOnSnapshotChangedSavesSnapshotAndShowsAlert() {
        final class SpyStore: AccountPoolStoring {
            var savedSnapshots: [AccountPoolSnapshot] = []

            func load() -> AccountPoolSnapshot? { nil }

            func save(_ snapshot: AccountPoolSnapshot) {
                savedSnapshots.append(snapshot)
            }
        }

        var state = AccountPoolState(
            accounts: [AgentAccount(id: UUID(), name: "A", usedUnits: 95, quota: 100)],
            mode: .focus,
            lowUsageThresholdRatio: 0.15
        )
        state.evaluate()
        let snapshot = state.snapshot
        let coordinator = PoolDashboardLifecycleFlowCoordinator()
        let store = SpyStore()

        let output = coordinator.onSnapshotChanged(
            snapshot: snapshot,
            state: state,
            lowUsageAlertPolicy: LowUsageAlertPolicy(),
            viewState: PoolDashboardViewState(),
            store: store
        )

        #expect(store.savedSnapshots.count == 1)
        #expect(output.viewState.showLowUsageAlert)
    }

    @Test
    func poolDashboardLifecycleFlowCoordinatorOnSnapshotChangedSavesSnapshotWithoutAlertWhenSafe() {
        final class SpyStore: AccountPoolStoring {
            var savedSnapshots: [AccountPoolSnapshot] = []

            func load() -> AccountPoolSnapshot? { nil }

            func save(_ snapshot: AccountPoolSnapshot) {
                savedSnapshots.append(snapshot)
            }
        }

        var state = AccountPoolState(
            accounts: [AgentAccount(id: UUID(), name: "A", usedUnits: 10, quota: 100)],
            mode: .manual,
            lowUsageThresholdRatio: 0.15
        )
        state.evaluate()
        let snapshot = state.snapshot
        let coordinator = PoolDashboardLifecycleFlowCoordinator()
        let store = SpyStore()

        let output = coordinator.onSnapshotChanged(
            snapshot: snapshot,
            state: state,
            lowUsageAlertPolicy: LowUsageAlertPolicy(),
            viewState: PoolDashboardViewState(),
            store: store
        )

        #expect(store.savedSnapshots.count == 1)
        #expect(!output.viewState.showLowUsageAlert)
    }

    @Test
    func poolDashboardMutationCoordinatorApplySyncOutputUpdatesAllFields() {
        let id = UUID()
        var state = AccountPoolState(
            accounts: [AgentAccount(id: id, name: "Old", usedUnits: 1, quota: 100)],
            mode: .manual
        )
        var viewState = PoolDashboardViewState(
            backupJSON: "",
            backupError: nil,
            syncError: "old",
            lastUsageRawJSON: "",
            showUsageRawJSON: false,
            oauthError: nil,
            oauthSuccessMessage: nil,
            lastSwitchLaunchLog: "",
            showSwitchLaunchLog: false
        )
        var nextState = state
        nextState.updateAccount(id, usedUnits: 77)
        let output = PoolDashboardRuntimeCoordinator.SyncOutput(
            state: nextState,
            syncError: nil,
            lastUsageRawJSON: "{\"ok\":true}"
        )
        let coordinator = PoolDashboardMutationCoordinator()

        coordinator.applySyncOutput(
            output,
            state: &state,
            viewState: &viewState
        )

        #expect(state.accounts[0].usedUnits == 77)
        #expect(viewState.lastUsageRawJSON == "{\"ok\":true}")
        #expect(viewState.syncError == nil)
    }

    @Test
    func poolDashboardMutationCoordinatorApplyOAuthOutputReturnsRefreshFlag() {
        let id = UUID()
        var state = AccountPoolState(
            accounts: [AgentAccount(id: id, name: "Old", usedUnits: 1, quota: 100)],
            mode: .manual
        )
        var viewState = PoolDashboardViewState(
            backupJSON: "",
            backupError: nil,
            syncError: nil,
            lastUsageRawJSON: "",
            showUsageRawJSON: false,
            oauthError: "old-error",
            oauthSuccessMessage: nil,
            lastSwitchLaunchLog: "",
            showSwitchLaunchLog: false
        )
        var oauthAccountName = "before"
        var updatedState = state
        updatedState.updateAccount(id, name: "Updated")
        let output = PoolDashboardRuntimeCoordinator.OAuthSignInOutput(
            state: updatedState,
            oauthError: nil,
            oauthSuccessMessage: "ok",
            nextOAuthAccountName: "",
            shouldRefreshLocalOAuthAccounts: true
        )
        let coordinator = PoolDashboardMutationCoordinator()

        let shouldRefresh = coordinator.applyOAuthOutput(
            output,
            state: &state,
            viewState: &viewState,
            oauthAccountName: &oauthAccountName
        )

        #expect(shouldRefresh)
        #expect(state.accounts[0].name == "Updated")
        #expect(viewState.oauthError == nil)
        #expect(viewState.oauthSuccessMessage == "ok")
        #expect(oauthAccountName.isEmpty)
    }

    @Test
    func poolDashboardMutationCoordinatorApplyLocalImportOutputClearsSyncErrorWhenImported() {
        var state = AccountPoolState(accounts: [], mode: .manual)
        var viewModel = LocalOAuthImportViewModel()
        var viewState = PoolDashboardViewState(
            backupJSON: "",
            backupError: nil,
            syncError: "previous",
            lastUsageRawJSON: "",
            showUsageRawJSON: false,
            oauthError: nil,
            oauthSuccessMessage: nil,
            lastSwitchLaunchLog: "",
            showSwitchLaunchLog: false
        )
        var nextState = state
        nextState.addAccount(name: "Imported", quota: 100)
        var nextViewModel = viewModel
        nextViewModel.errorMessage = nil
        let output = PoolDashboardLocalImportCoordinator.Output(
            state: nextState,
            viewModel: nextViewModel,
            didImport: true
        )
        let coordinator = PoolDashboardMutationCoordinator()

        coordinator.applyLocalImportOutput(
            output,
            state: &state,
            viewModel: &viewModel,
            viewState: &viewState
        )

        #expect(state.accounts.count == 1)
        #expect(viewState.syncError == nil)
    }

    @Test
    func poolDashboardMutationCoordinatorApplySwitchOutputUpdatesViewModelAndLog() {
        var viewModel = LocalOAuthImportViewModel()
        var viewState = PoolDashboardViewState(
            backupJSON: "",
            backupError: nil,
            syncError: nil,
            lastUsageRawJSON: "",
            showUsageRawJSON: false,
            oauthError: nil,
            oauthSuccessMessage: nil,
            lastSwitchLaunchLog: "",
            showSwitchLaunchLog: false
        )
        var authorizedURL: URL? = nil
        let expectedURL = URL(string: "file:///tmp/auth.json")
        let output = PoolDashboardSwitchLaunchCoordinator.Output(
            switchLaunchLog: "line-1",
            errorMessage: "switch-failed",
            sessionAuthorizedAuthFileURL: expectedURL
        )
        let coordinator = PoolDashboardMutationCoordinator()

        coordinator.applySwitchOutput(
            output,
            viewModel: &viewModel,
            viewState: &viewState,
            sessionAuthorizedAuthFileURL: &authorizedURL
        )

        #expect(viewState.lastSwitchLaunchLog == "line-1")
        #expect(viewModel.errorMessage == "switch-failed")
        #expect(authorizedURL == expectedURL)
    }

    @Test
    func poolDashboardActionCoordinatorAddAndRemoveAccount() {
        var state = AccountPoolState(accounts: [], mode: .manual)
        let coordinator = PoolDashboardActionCoordinator()

        coordinator.addAccount(state: &state, name: "Added", quota: 123)
        let addedID = state.accounts[0].id
        #expect(state.accounts.count == 1)
        #expect(state.accounts[0].name == "Added")
        #expect(state.accounts[0].quota == 123)

        coordinator.removeAccount(state: &state, accountID: addedID)
        #expect(state.accounts.isEmpty)
    }

    @Test
    func poolDashboardActionCoordinatorResetAllUsage() {
        let a = UUID()
        let b = UUID()
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: a, name: "A", usedUnits: 30, quota: 100),
                AgentAccount(id: b, name: "B", usedUnits: 50, quota: 100)
            ],
            mode: .manual
        )
        let coordinator = PoolDashboardActionCoordinator()

        coordinator.resetAllUsage(state: &state)

        #expect(state.accounts[0].usedUnits == 0)
        #expect(state.accounts[1].usedUnits == 0)
    }

    @Test
    func poolDashboardActionCoordinatorSimulateUsageAndEvaluate() {
        let id = UUID()
        var state = AccountPoolState(
            accounts: [AgentAccount(id: id, name: "A", usedUnits: 0, quota: 100)],
            mode: .manual
        )
        state.selectManualAccount(id)
        let coordinator = PoolDashboardActionCoordinator()

        coordinator.evaluateSwitch(state: &state)
        coordinator.simulateUsage(state: &state, units: 17)

        #expect(state.activeAccount?.id == id)
        #expect(state.accounts[0].usedUnits == 17)
    }

    @Test
    func poolDashboardActionCoordinatorClearActivities() {
        var state = AccountPoolState(
            accounts: [AgentAccount(id: UUID(), name: "A", usedUnits: 0, quota: 100)],
            mode: .manual
        )
        state.addAccount(name: "B", quota: 100)
        #expect(!state.activities.isEmpty)
        let coordinator = PoolDashboardActionCoordinator()

        coordinator.clearActivities(state: &state)

        #expect(state.activities.isEmpty)
    }

    @Test
    func poolDashboardAlertPresenterBuildsLowUsageMessageForActiveAccount() {
        let presenter = PoolDashboardAlertPresenter()
        let account = AgentAccount(
            id: UUID(),
            name: "Codex A",
            usedUnits: 90,
            quota: 100
        )

        let message = presenter.lowUsageAlertMessage(
            activeAccount: account,
            thresholdRatio: 0.15
        )

        #expect(message == "Codex A 剩餘 10，已低於 15% 門檻。")
    }

    @Test
    func poolDashboardAlertPresenterBuildsFallbackMessageWhenNoActiveAccount() {
        let presenter = PoolDashboardAlertPresenter()

        let message = presenter.lowUsageAlertMessage(
            activeAccount: nil,
            thresholdRatio: 0.15
        )

        #expect(message == "目前帳號剩餘用量偏低。")
    }

    @Test
    func poolDashboardBackupCoordinatorImportSnapshotStateReturnsFailureForInvalidJSON() {
        let coordinator = PoolDashboardBackupCoordinator()

        let result = coordinator.importSnapshotState(from: "{ invalid-json }")

        #expect(result.state == nil)
        #expect(result.errorMessage?.hasPrefix("匯入失敗：") == true)
    }

    @Test
    func poolDashboardActionCoordinatorSimulateUsageUsesDefaultUnits50() {
        let id = UUID()
        var state = AccountPoolState(
            accounts: [AgentAccount(id: id, name: "A", usedUnits: 0, quota: 100)],
            mode: .manual
        )
        state.selectManualAccount(id)
        state.evaluate()
        let coordinator = PoolDashboardActionCoordinator()

        coordinator.simulateUsage(state: &state)

        #expect(state.accounts[0].usedUnits == 50)
    }

    @Test
    func poolDashboardViewStateDefaultsMatchExpected() {
        let viewState = PoolDashboardViewState()

        #expect(viewState.showLowUsageAlert == false)
        #expect(viewState.isSyncingUsage == false)
        #expect(viewState.isSigningInOAuth == false)
        #expect(viewState.backupJSON.isEmpty)
        #expect(viewState.syncError == nil)
        #expect(viewState.oauthError == nil)
        #expect(viewState.lastSwitchLaunchLog.isEmpty)
    }

    @Test
    func poolDashboardFormStateDefaultsMatchExpected() {
        let formState = PoolDashboardFormState()

        #expect(formState.newAccountName.isEmpty)
        #expect(formState.newAccountQuota == 1000)
        #expect(formState.oauthAccountName.isEmpty)
        #expect(formState.oauthAccountQuota == 1000)
    }
}

extension AIAgentPoolTests {

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
    func oauthCallbackParserThrowsAuthorizationFailedWhenErrorPresent() throws {
        let callbackURL = try #require(
            URL(string: "aiaagentpool://oauth/callback?error=access_denied")
        )

        #expect(throws: OAuthLoginError.authorizationFailed("access_denied")) {
            _ = try OAuthCallbackParser.parse(callbackURL: callbackURL)
        }
    }

    @Test
    func oauthCallbackParserThrowsMissingCodeWhenCodeMissing() throws {
        let callbackURL = try #require(
            URL(string: "aiaagentpool://oauth/callback?state=s1")
        )

        #expect(throws: OAuthLoginError.missingCode) {
            _ = try OAuthCallbackParser.parse(callbackURL: callbackURL)
        }
    }

    @Test
    func oauthCallbackParserThrowsStateMismatchWhenStateMissing() throws {
        let callbackURL = try #require(
            URL(string: "aiaagentpool://oauth/callback?code=abc123")
        )

        #expect(throws: OAuthLoginError.stateMismatch) {
            _ = try OAuthCallbackParser.parse(callbackURL: callbackURL)
        }
    }

    @Test
    func oauthCallbackParserParsesCodeAndStateForCustomScheme() throws {
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
    func oauthLocalhostCallbackConfigUsesDefaultPortWhenMissing() throws {
        let redirectURI = try #require(URL(string: "http://localhost/auth/callback"))

        let config = try #require(LocalhostOAuthCallbackConfig(redirectURI: redirectURI))

        #expect(config.port == 80)
    }

    @Test
    func oauthLocalhostCallbackConfigRejectsNonLocalhostHost() throws {
        let redirectURI = try #require(URL(string: "http://example.com/auth/callback"))

        #expect(LocalhostOAuthCallbackConfig(redirectURI: redirectURI) == nil)
    }

    @Test
    func oauthLocalhostCallbackConfigRejectsNonHttpScheme() throws {
        let redirectURI = try #require(URL(string: "aiaagentpool://oauth/callback"))

        #expect(LocalhostOAuthCallbackConfig(redirectURI: redirectURI) == nil)
    }

    @Test
    func oauthLocalhostCallbackExtractorParsesCodeAndStateFromRequestLine() throws {
        let config = LocalhostOAuthCallbackConfig(host: "localhost", port: 1455, callbackPath: "/auth/callback")
        let request = "GET /auth/callback?code=abc123&state=s1 HTTP/1.1\r\nHost: localhost:1455\r\n\r\n"

        let callbackURL = try #require(LocalhostOAuthCallbackExtractor.callbackURL(fromRequest: request, config: config))

        #expect(callbackURL.absoluteString == "http://localhost:1455/auth/callback?code=abc123&state=s1")
    }

    @Test
    func oauthLocalhostCallbackExtractorReturnsNilForWrongPath() {
        let config = LocalhostOAuthCallbackConfig(host: "localhost", port: 1455, callbackPath: "/auth/callback")
        let request = "GET /wrong/path?code=abc&state=s1 HTTP/1.1\r\nHost: localhost:1455\r\n\r\n"

        let callbackURL = LocalhostOAuthCallbackExtractor.callbackURL(fromRequest: request, config: config)

        #expect(callbackURL == nil)
    }

    @Test
    func oauthLocalhostCallbackExtractorReturnsNilForNonGetMethod() {
        let config = LocalhostOAuthCallbackConfig(host: "localhost", port: 1455, callbackPath: "/auth/callback")
        let request = "POST /auth/callback?code=abc&state=s1 HTTP/1.1\r\nHost: localhost:1455\r\n\r\n"

        let callbackURL = LocalhostOAuthCallbackExtractor.callbackURL(fromRequest: request, config: config)

        #expect(callbackURL == nil)
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
    func oauthIDTokenClaimsParserReturnsNilForMalformedToken() {
        #expect(OAuthIDTokenClaimsParser.parse("not.a.jwt") == nil)
        #expect(OAuthIDTokenClaimsParser.parse("header.invalid_base64.sig") == nil)
        #expect(OAuthIDTokenClaimsParser.parse(nil) == nil)
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
    func oauthAccountUpsertResolverReturnsNilWhenNoCandidateMatches() {
        let accounts = [
            AgentAccount(
                id: UUID(),
                name: "someone@example.com",
                usedUnits: 10,
                quota: 100,
                apiToken: "token-a",
                chatGPTAccountID: "acct-a"
            )
        ]

        let matched = OAuthAccountUpsertResolver.resolveExistingAccountID(
            in: accounts,
            chatGPTAccountID: "acct-b",
            accessToken: "token-b",
            email: "other@example.com"
        )

        #expect(matched == nil)
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
        #expect(form.contains("redirect_uri=aiaagentpool://oauth/callback"))
        #expect(form.contains("code_verifier=verifier-123"))
    }

    @Test
    func poolAccountUpsertOAuthSignInAddsNewAccountWhenNoMatch() {
        var state = AccountPoolState(accounts: [], mode: .manual)
        let coordinator = PoolAccountUpsertCoordinator()
        let tokens = OAuthTokens(accessToken: "token-new", refreshToken: nil, idToken: nil)
        let claims = OAuthIDTokenClaims(subject: "user-1", accountID: "acct-1", email: "new@example.com")

        let message = coordinator.applyOAuthSignIn(
            state: &state,
            tokens: tokens,
            claims: claims,
            usage: nil,
            accountNameInput: "",
            fallbackQuota: 1000
        )

        #expect(message == "登入成功，已新增帳號")
        #expect(state.accounts.count == 1)
        #expect(state.accounts[0].name == "new@example.com")
        #expect(state.accounts[0].apiToken == "token-new")
        #expect(state.accounts[0].chatGPTAccountID == "acct-1")
        #expect(state.accounts[0].quota == 1000)
        #expect(state.accounts[0].usedUnits == 0)
    }

    @Test
    func poolAccountUpsertOAuthSignInUpdatesPlaceholderNameWhenMatched() {
        let accountID = UUID()
        var state = AccountPoolState(
            accounts: [
                AgentAccount(
                    id: accountID,
                    name: "OAuth Account",
                    usedUnits: 0,
                    quota: 100,
                    apiToken: "token-old",
                    chatGPTAccountID: "acct-1"
                )
            ],
            mode: .manual
        )
        let coordinator = PoolAccountUpsertCoordinator()
        let tokens = OAuthTokens(accessToken: "token-new", refreshToken: nil, idToken: nil)
        let claims = OAuthIDTokenClaims(subject: "user-1", accountID: "acct-1", email: "real@example.com")

        let message = coordinator.applyOAuthSignIn(
            state: &state,
            tokens: tokens,
            claims: claims,
            usage: CodexUsage(usedUnits: 11, quota: 100, accountID: "acct-1", accountEmail: "real@example.com"),
            accountNameInput: "",
            fallbackQuota: 1000
        )

        #expect(message == "登入成功，已更新既有帳號")
        #expect(state.accounts.count == 1)
        #expect(state.accounts[0].id == accountID)
        #expect(state.accounts[0].name == "real@example.com")
        #expect(state.accounts[0].apiToken == "token-new")
        #expect(state.accounts[0].usedUnits == 11)
        #expect(state.accounts[0].quota == 100)
    }

    @Test
    func poolAccountUpsertOAuthSignInKeepsExistingCustomNameWhenInputIsEmpty() {
        let accountID = UUID()
        var state = AccountPoolState(
            accounts: [
                AgentAccount(
                    id: accountID,
                    name: "Custom Name",
                    usedUnits: 0,
                    quota: 100,
                    apiToken: "token-old",
                    chatGPTAccountID: "acct-1"
                )
            ],
            mode: .manual
        )
        let coordinator = PoolAccountUpsertCoordinator()
        let tokens = OAuthTokens(accessToken: "token-new", refreshToken: nil, idToken: nil)
        let claims = OAuthIDTokenClaims(subject: "user-1", accountID: "acct-1", email: "real@example.com")

        _ = coordinator.applyOAuthSignIn(
            state: &state,
            tokens: tokens,
            claims: claims,
            usage: CodexUsage(usedUnits: 5, quota: 100),
            accountNameInput: "",
            fallbackQuota: 1000
        )

        #expect(state.accounts[0].name == "Custom Name")
    }

    @Test
    func poolAccountUpsertLocalImportUpdatesExistingAccountByAccountID() {
        let existingID = UUID()
        var state = AccountPoolState(
            accounts: [
                AgentAccount(
                    id: existingID,
                    name: "old@example.com",
                    usedUnits: 0,
                    quota: 100,
                    apiToken: "token-old",
                    chatGPTAccountID: "acct-1"
                )
            ],
            mode: .manual
        )
        let coordinator = PoolAccountUpsertCoordinator()
        let usage = CodexUsage(
            usedUnits: 42,
            quota: 100,
            usageWindowName: "primary_window",
            usageWindowResetAt: Date(timeIntervalSince1970: 1_700_000_000),
            accountID: "acct-1",
            accountEmail: "new@example.com"
        )

        coordinator.applyLocalImport(
            state: &state,
            usage: usage,
            fallbackName: "fallback",
            accessToken: "token-new",
            chatGPTAccountID: "acct-1"
        )

        #expect(state.accounts.count == 1)
        #expect(state.accounts[0].id == existingID)
        #expect(state.accounts[0].name == "new@example.com")
        #expect(state.accounts[0].apiToken == "token-new")
        #expect(state.accounts[0].usedUnits == 42)
        #expect(state.accounts[0].usageWindowName == "primary_window")
    }

    @Test
    func poolDashboardLifecycleCoordinatorOnAppearEvaluatesState() {
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: UUID(), name: "A", usedUnits: 90, quota: 100),
                AgentAccount(id: UUID(), name: "B", usedUnits: 10, quota: 100)
            ],
            mode: .intelligent
        )
        var policy = LowUsageAlertPolicy()
        let coordinator = PoolDashboardLifecycleCoordinator()

        coordinator.onAppear(state: &state, lowUsageAlertPolicy: &policy)

        #expect(state.activeAccount?.name == "B")
    }

    @Test
    func poolDashboardLifecycleCoordinatorShouldShowLowUsageAlertTriggersOnce() {
        var state = AccountPoolState(
            accounts: [AgentAccount(id: UUID(), name: "A", usedUnits: 95, quota: 100)],
            mode: .focus,
            lowUsageThresholdRatio: 0.15
        )
        state.evaluate()
        var policy = LowUsageAlertPolicy()
        let coordinator = PoolDashboardLifecycleCoordinator()

        let first = coordinator.shouldShowLowUsageAlert(
            state: state,
            lowUsageAlertPolicy: &policy
        )
        let second = coordinator.shouldShowLowUsageAlert(
            state: state,
            lowUsageAlertPolicy: &policy
        )

        #expect(first)
        #expect(!second)
    }

    @Test
    func poolDashboardMutationCoordinatorApplySyncOutputUpdatesStateAndRawAndError() {
        let coordinator = PoolDashboardMutationCoordinator()
        let accountID = UUID()
        var state = AccountPoolState(accounts: [], mode: .manual)
        var viewState = PoolDashboardViewState()
        let output = PoolDashboardRuntimeCoordinator.SyncOutput(
            state: AccountPoolState(
                accounts: [AgentAccount(id: accountID, name: "Synced", usedUnits: 10, quota: 100)],
                mode: .manual
            ),
            syncError: "同步失敗：x",
            lastUsageRawJSON: "{\"ok\":true}"
        )

        coordinator.applySyncOutput(
            output,
            state: &state,
            viewState: &viewState
        )

        #expect(state.accounts.count == 1)
        #expect(state.accounts[0].name == "Synced")
        #expect(viewState.lastUsageRawJSON == "{\"ok\":true}")
        #expect(viewState.syncError == "同步失敗：x")
    }

    @Test
    func poolDashboardMutationCoordinatorApplyOAuthOutputReturnsRefreshFlagAndWritesFields() {
        let coordinator = PoolDashboardMutationCoordinator()
        var state = AccountPoolState(accounts: [], mode: .manual)
        var viewState = PoolDashboardViewState()
        var oauthAccountName = "old"
        let output = PoolDashboardRuntimeCoordinator.OAuthSignInOutput(
            state: AccountPoolState(
                accounts: [AgentAccount(id: UUID(), name: "OAuth", usedUnits: 0, quota: 100)],
                mode: .manual
            ),
            oauthError: nil,
            oauthSuccessMessage: "success",
            nextOAuthAccountName: "",
            shouldRefreshLocalOAuthAccounts: true
        )

        let shouldRefresh = coordinator.applyOAuthOutput(
            output,
            state: &state,
            viewState: &viewState,
            oauthAccountName: &oauthAccountName
        )

        #expect(shouldRefresh)
        #expect(state.accounts.count == 1)
        #expect(viewState.oauthError == nil)
        #expect(viewState.oauthSuccessMessage == "success")
        #expect(oauthAccountName == "")
    }

    @Test
    func poolDashboardMutationCoordinatorApplySwitchOutputWritesLogErrorAndSessionURL() {
        let coordinator = PoolDashboardMutationCoordinator()
        var viewModel = LocalOAuthImportViewModel()
        var viewState = PoolDashboardViewState()
        var url: URL? = nil
        let expectedURL = URL(string: "file:///tmp/auth.json")
        let output = PoolDashboardSwitchLaunchCoordinator.Output(
            switchLaunchLog: "log-line",
            errorMessage: "err",
            sessionAuthorizedAuthFileURL: expectedURL
        )

        coordinator.applySwitchOutput(
            output,
            viewModel: &viewModel,
            viewState: &viewState,
            sessionAuthorizedAuthFileURL: &url
        )

        #expect(viewState.lastSwitchLaunchLog == "log-line")
        #expect(viewModel.errorMessage == "err")
        #expect(url == expectedURL)
    }

    @Test
    func poolDashboardMutationCoordinatorApplyBackupExportResultWritesJSONAndClearsError() {
        let coordinator = PoolDashboardMutationCoordinator()
        var viewState = PoolDashboardViewState()
        viewState.backupError = "old"

        coordinator.applyBackupExportResult((json: "{\"ok\":true}", errorMessage: nil), viewState: &viewState)

        #expect(viewState.backupJSON == "{\"ok\":true}")
        #expect(viewState.backupError == nil)
    }

    @Test
    func poolDashboardMutationCoordinatorApplyBackupExportResultWritesErrorWhenFailed() {
        let coordinator = PoolDashboardMutationCoordinator()
        var viewState = PoolDashboardViewState()

        coordinator.applyBackupExportResult((json: nil, errorMessage: "匯出失敗"), viewState: &viewState)

        #expect(viewState.backupError == "匯出失敗")
    }

    @Test
    func poolDashboardMutationCoordinatorApplyBackupImportResultWritesStateAndReturnsTrue() {
        let coordinator = PoolDashboardMutationCoordinator()
        let accountID = UUID()
        var state = AccountPoolState(accounts: [], mode: .manual)
        var viewState = PoolDashboardViewState()
        viewState.backupError = "old"

        let shouldSync = coordinator.applyBackupImportResult(
            (
                state: AccountPoolState(
                    accounts: [AgentAccount(id: accountID, name: "Imported", usedUnits: 0, quota: 200)],
                    mode: .manual
                ),
                errorMessage: nil
            ),
            state: &state,
            viewState: &viewState
        )

        #expect(shouldSync)
        #expect(state.accounts.count == 1)
        #expect(state.accounts[0].name == "Imported")
        #expect(viewState.backupError == nil)
    }

    @Test
    func poolDashboardMutationCoordinatorApplyBackupImportResultWritesErrorAndReturnsFalse() {
        let coordinator = PoolDashboardMutationCoordinator()
        var state = AccountPoolState(accounts: [], mode: .manual)
        var viewState = PoolDashboardViewState()

        let shouldSync = coordinator.applyBackupImportResult(
            (state: nil, errorMessage: "匯入失敗"),
            state: &state,
            viewState: &viewState
        )

        #expect(!shouldSync)
        #expect(viewState.backupError == "匯入失敗")
    }

}
