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
            mode: .focus,
            activeAccountID: accountID,
            manualAccountID: accountID,
            focusLockedAccountID: accountID
        )

        store.save(snapshot)
        let loaded = store.load()

        #expect(loaded == snapshot)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
