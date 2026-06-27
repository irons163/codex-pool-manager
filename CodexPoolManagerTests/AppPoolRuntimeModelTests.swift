import Foundation
import Testing

@testable import CodexPoolManager

@MainActor
struct AppPoolRuntimeModelTests {
    final class SpyStore: AccountPoolStoring {
        var loadedSnapshot: AccountPoolSnapshot?
        var savedSnapshots: [AccountPoolSnapshot] = []
        var tokens: [UUID: String] = [:]
        var loadCount = 0

        func load() -> AccountPoolSnapshot? {
            loadCount += 1
            return loadedSnapshot
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
        var publishedSnapshots: [AccountPoolSnapshot] = []
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: makeState(name: "before@example.com"),
            widgetPublisher: { snapshot in
                publishedSnapshots.append(snapshot)
            },
            syncRunner: { state, _ in
                var nextViewState = PoolDashboardViewState()
                syncCallCount += 1
                if syncCallCount == 1 {
                    var failedOutputState = state
                    failedOutputState.updateAccount(
                        state.accounts[0].id,
                        name: "failed-output@example.com",
                        usedUnits: 99
                    )
                    nextViewState.syncError = "offline"
                    return PoolDashboardUsageSyncFlowCoordinator.Output(
                        state: failedOutputState,
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
        #expect(store.savedSnapshots.last?.accounts.first?.usedUnits == 10)
        #expect(publishedSnapshots.contains { $0.accounts.first?.usedUnits == 10 })
        #expect(!store.savedSnapshots.contains {
            $0.accounts.first?.name == "failed-output@example.com"
            || $0.accounts.first?.usedUnits == 99
        })
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
        #expect(!store.savedSnapshots.contains {
            $0.accounts.first?.name == "mutated@example.com"
            || $0.accounts.first?.usedUnits == 99
        })
    }

    @Test
    func syncNowDiscardsStaleOutputWhenDashboardStateChangesDuringSync() async {
        let store = SpyStore()
        var publishedSnapshots: [AccountPoolSnapshot] = []
        var outputContinuation: CheckedContinuation<PoolDashboardUsageSyncFlowCoordinator.Output, Never>?
        let (runnerStarted, runnerStartedContinuation) = AsyncStream<Void>.makeStream()
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: makeState(name: "before@example.com"),
            widgetPublisher: { snapshot in
                publishedSnapshots.append(snapshot)
            },
            syncRunner: { state, _ in
                await withCheckedContinuation { continuation in
                    outputContinuation = continuation
                    runnerStartedContinuation.yield(())
                }
            }
        )

        let syncTask = Task {
            await model.syncNow()
        }
        var runnerStartedIterator = runnerStarted.makeAsyncIterator()
        _ = await runnerStartedIterator.next()

        model.replaceStateFromDashboard(makeState(name: "dashboard@example.com"))

        var staleState = makeState(name: "synced-old@example.com")
        staleState.updateAccount(
            staleState.accounts[0].id,
            name: "synced-old@example.com",
            usedUnits: 5
        )
        outputContinuation?.resume(returning: PoolDashboardUsageSyncFlowCoordinator.Output(
            state: staleState,
            viewState: PoolDashboardViewState()
        ))

        await syncTask.value

        #expect(model.state.accounts.first?.name == "dashboard@example.com")
        #expect(model.isSyncingUsage == false)
        #expect(!store.savedSnapshots.contains {
            $0.accounts.first?.name == "synced-old@example.com"
        })
        #expect(!publishedSnapshots.contains {
            $0.accounts.first?.name == "synced-old@example.com"
        })
    }

    @Test
    func startAutoSyncIfNeededRunsImmediateSyncAndStopCancelsTask() async {
        let store = SpyStore()
        let (syncStarted, syncStartedContinuation) = AsyncStream<Void>.makeStream()
        var state = makeState(name: "autosync@example.com")
        state.setAutoSyncEnabled(true)
        state.setAutoSyncIntervalSeconds(5)
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: state,
            syncRunner: { state, _ in
                syncStartedContinuation.yield(())
                return PoolDashboardUsageSyncFlowCoordinator.Output(
                    state: state,
                    viewState: PoolDashboardViewState()
                )
            }
        )

        model.startAutoSyncIfNeeded()

        var iterator = syncStarted.makeAsyncIterator()
        _ = await iterator.next()
        model.stopAutoSync()

        #expect(store.savedSnapshots.count == 1)
    }

    @Test
    func bootstrapIfNeededLoadsPublishesAndStartsAutoSyncOnlyOnce() async {
        let store = SpyStore()
        var state = makeState(name: "bootstrap@example.com")
        state.setAutoSyncEnabled(true)
        store.loadedSnapshot = state.snapshot
        var publishedNames: [String] = []
        var syncCallCount = 0
        let (syncStarted, syncStartedContinuation) = AsyncStream<Void>.makeStream()
        let model = AppPoolRuntimeModel(
            store: store,
            widgetPublisher: { snapshot in
                publishedNames.append(snapshot.accounts.first?.name ?? "")
            },
            syncRunner: { state, _ in
                syncCallCount += 1
                syncStartedContinuation.yield(())
                return PoolDashboardUsageSyncFlowCoordinator.Output(
                    state: state,
                    viewState: PoolDashboardViewState()
                )
            }
        )

        model.bootstrapIfNeeded()

        var iterator = syncStarted.makeAsyncIterator()
        _ = await iterator.next()
        let publishedCountAfterFirstBootstrap = publishedNames.count
        let savedCountAfterFirstBootstrap = store.savedSnapshots.count
        model.bootstrapIfNeeded()
        model.stopAutoSync()

        #expect(model.state.accounts.first?.name == "bootstrap@example.com")
        #expect(store.loadCount == 1)
        #expect(publishedNames.count == publishedCountAfterFirstBootstrap)
        #expect(publishedNames.allSatisfy { $0 == "bootstrap@example.com" })
        #expect(syncCallCount == 1)
        #expect(store.savedSnapshots.count == savedCountAfterFirstBootstrap)
    }
}
