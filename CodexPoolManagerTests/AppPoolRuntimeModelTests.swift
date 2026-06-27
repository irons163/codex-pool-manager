import Foundation
import Testing

@testable import CodexPoolManager

@MainActor
struct AppPoolRuntimeModelTests {
    final class SpyStore: AccountPoolStoring {
        var loadedSnapshot: AccountPoolSnapshot?
        var savedSnapshots: [AccountPoolSnapshot] = []
        var tokens: [UUID: String] = [:]

        func load() -> AccountPoolSnapshot? {
            loadedSnapshot
        }

        func save(_ snapshot: AccountPoolSnapshot) {
            savedSnapshots.append(snapshot)
            loadedSnapshot = snapshot
        }

        func removeToken(for accountID: UUID) {
            tokens[accountID] = nil
        }

        func apiToken(for accountID: UUID) -> String? {
            tokens[accountID]
        }
    }

    private func makeState(name: String = "alpha@example.com") -> AccountPoolState {
        let account = AgentAccount(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: name,
            usedUnits: 40,
            quota: 100,
            chatGPTAccountID: "user-alpha",
            usageWindowResetAt: Date(timeIntervalSince1970: 2_000),
            primaryUsagePercent: 30,
            primaryUsageResetAt: Date(timeIntervalSince1970: 1_600),
            isPaid: true
        )
        var state = AccountPoolState(accounts: [account], mode: .manual)
        state.markActiveAccountForSwitchLaunch(account.id, now: Date(timeIntervalSince1970: 1_000))
        state.markUsageSynced(at: Date(timeIntervalSince1970: 1_000))
        return state
    }

    @Test
    func loadUsesStoreSnapshotAndPublishesWidgetSnapshot() {
        let store = SpyStore()
        store.loadedSnapshot = makeState(name: "loaded@example.com").snapshot
        var publishedNames: [String] = []
        let model = AppPoolRuntimeModel(
            store: store,
            widgetPublisher: { snapshot in
                publishedNames.append(snapshot.accounts.first?.name ?? "")
            }
        )

        model.load()

        #expect(model.state.accounts.first?.name == "loaded@example.com")
        #expect(store.savedSnapshots.isEmpty)
        #expect(publishedNames == ["loaded@example.com"])
        #expect(model.menuBarSnapshot.activeAccount?.name == "loaded@example.com")
    }

    @Test
    func replaceFromDashboardSavesAndPublishesOnce() {
        let store = SpyStore()
        var publishedNames: [String] = []
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: makeState(name: "initial@example.com"),
            widgetPublisher: { snapshot in
                publishedNames.append(snapshot.accounts.first?.name ?? "")
            }
        )

        model.replaceStateFromDashboard(makeState(name: "dashboard@example.com"))

        #expect(model.state.accounts.first?.name == "dashboard@example.com")
        #expect(store.savedSnapshots.count == 1)
        #expect(store.savedSnapshots.first?.accounts.first?.name == "dashboard@example.com")
        #expect(publishedNames == ["dashboard@example.com"])
    }

    @Test
    func syncNowUsesInjectedRunnerAndSavesReturnedState() async {
        let store = SpyStore()
        var syncCallCount = 0
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: makeState(name: "before@example.com"),
            syncRunner: { state, _ in
                var nextViewState = PoolDashboardViewState()
                syncCallCount += 1
                if syncCallCount == 1 {
                    nextViewState.syncError = "offline"
                    return PoolDashboardUsageSyncFlowCoordinator.Output(
                        state: state,
                        viewState: nextViewState
                    )
                }

                var next = state
                next.updateAccount(
                    state.accounts[0].id,
                    usedUnits: 10,
                    usageWindowResetAt: Date(timeIntervalSince1970: 3_000),
                    primaryUsagePercent: 20,
                    primaryUsageResetAt: Date(timeIntervalSince1970: 2_400)
                )
                return PoolDashboardUsageSyncFlowCoordinator.Output(
                    state: next,
                    viewState: nextViewState
                )
            }
        )

        await model.syncNow()
        #expect(model.lastSyncError == "offline")
        #expect(model.state.accounts.first?.name == "before@example.com")

        await model.syncNow()

        #expect(syncCallCount == 2)
        #expect(model.isSyncingUsage == false)
        #expect(model.lastSyncError == nil)
        #expect(model.state.accounts.first?.usedUnits == 10)
        #expect(store.savedSnapshots.count == 2)
        #expect(store.savedSnapshots.last?.accounts.first?.usedUnits == 10)
    }

    @Test
    func syncNowStoresErrorWithoutDroppingPreviousState() async {
        let store = SpyStore()
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: makeState(name: "stable@example.com"),
            syncRunner: { state, _ in
                var mutatedState = state
                mutatedState.updateAccount(
                    state.accounts[0].id,
                    name: "mutated@example.com",
                    usedUnits: 99
                )
                var nextViewState = PoolDashboardViewState()
                nextViewState.syncError = "offline"
                return PoolDashboardUsageSyncFlowCoordinator.Output(
                    state: mutatedState,
                    viewState: nextViewState
                )
            }
        )

        await model.syncNow()

        #expect(model.lastSyncError == "offline")
        #expect(model.state.accounts.first?.name == "stable@example.com")
        #expect(model.state.accounts.first?.usedUnits == 40)
        #expect(store.savedSnapshots.count == 1)
        #expect(store.savedSnapshots.first?.accounts.first?.name == "stable@example.com")
        #expect(store.savedSnapshots.first?.accounts.first?.usedUnits == 40)
    }
}
