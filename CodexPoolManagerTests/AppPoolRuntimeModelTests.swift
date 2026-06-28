import Combine
import Foundation
import Testing

@testable import CodexPoolManager

@Suite(.serialized)
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

    private func makeTwoAccountState() -> AccountPoolState {
        let firstID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let secondID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let first = AgentAccount(
            id: firstID,
            name: "alpha@example.com",
            usedUnits: 40,
            quota: 100,
            chatGPTAccountID: "user-alpha",
            usageWindowResetAt: Date(timeIntervalSince1970: 2_000),
            primaryUsagePercent: 30,
            primaryUsageResetAt: Date(timeIntervalSince1970: 1_600),
            isPaid: true
        )
        let second = AgentAccount(
            id: secondID,
            name: "beta@example.com",
            usedUnits: 20,
            quota: 100,
            chatGPTAccountID: "user-beta",
            usageWindowResetAt: Date(timeIntervalSince1970: 2_200),
            primaryUsagePercent: 10,
            primaryUsageResetAt: Date(timeIntervalSince1970: 1_800),
            isPaid: true
        )
        var state = AccountPoolState(accounts: [first, second], mode: .manual)
        state.markActiveAccountForSwitchLaunch(firstID, now: Date(timeIntervalSince1970: 1_000))
        state.markUsageSynced(at: Date(timeIntervalSince1970: 1_000))
        return state
    }

    private func nextValue<T>(
        from stream: AsyncStream<T>,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }
            let value = await group.next() ?? nil
            group.cancelAll()
            return value
        }
    }

    private func nextOutcome(
        from stream: AsyncStream<AppPoolRuntimeModel.SyncOutcome>,
        matching status: AppPoolRuntimeSyncOutcomeStatus,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async -> AppPoolRuntimeModel.SyncOutcome? {
        await withTaskGroup(of: AppPoolRuntimeModel.SyncOutcome?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                while let outcome = await iterator.next() {
                    if await MainActor.run(body: { outcome.status == status }) {
                        return outcome
                    }
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }
            let value = await group.next() ?? nil
            group.cancelAll()
            return value
        }
    }

    @Test
    func initUsesStoreSnapshotBeforeBootstrapWithoutSavingEmptyState() {
        let store = SpyStore()
        store.loadedSnapshot = makeState(name: "persisted@example.com").snapshot
        var publishedSnapshots: [AccountPoolSnapshot] = []

        let model = AppPoolRuntimeModel(
            store: store,
            widgetPublisher: { snapshot in
                publishedSnapshots.append(snapshot)
            }
        )

        #expect(model.state.accounts.first?.name == "persisted@example.com")
        #expect(store.loadCount == 1)
        #expect(store.savedSnapshots.isEmpty)
        #expect(publishedSnapshots.isEmpty)
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
        let didStart: Void? = await nextValue(from: runnerStarted)
        #expect(didStart != nil)

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

        let staleOutcome = await syncTask.value

        #expect(model.state.accounts.first?.name == "dashboard@example.com")
        #expect(model.isSyncingUsage == false)
        #expect(staleOutcome?.status == .staleDiscard)
        #expect(staleOutcome?.stateApplied == false)
        #expect(staleOutcome?.resultingState.accounts.first?.name == "dashboard@example.com")
        #expect(model.lastSyncOutcome?.id == staleOutcome?.id)
        #expect(!store.savedSnapshots.contains {
            $0.accounts.first?.name == "synced-old@example.com"
        })
        #expect(!publishedSnapshots.contains {
            $0.accounts.first?.name == "synced-old@example.com"
        })
    }

    @Test
    func switchAccountDiscardsStaleOutputWhenMenuSwitchChangesStateDuringSync() async {
        let store = SpyStore()
        let initialState = makeTwoAccountState()
        let firstID = initialState.accounts[0].id
        let secondID = initialState.accounts[1].id
        var outputContinuation: CheckedContinuation<PoolDashboardUsageSyncFlowCoordinator.Output, Never>?
        let (runnerStarted, runnerStartedContinuation) = AsyncStream<Void>.makeStream()
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: initialState,
            syncRunner: { _, _ in
                await withCheckedContinuation { continuation in
                    outputContinuation = continuation
                    runnerStartedContinuation.yield(())
                }
            },
            officialSwitchRunner: { _ in
                .success("switched")
            },
            relaySwitchRunner: { _ in
                Issue.record("relay runner must not be used for an OAuth account")
                return .failure("wrong runner")
            }
        )

        let syncTask = Task {
            await model.syncNow()
        }
        let didStart: Void? = await nextValue(from: runnerStarted)
        #expect(didStart != nil)

        await model.switchAccount(secondID)
        #expect(model.state.activeAccountID == secondID)

        var staleState = initialState
        staleState.markActiveAccountForSwitchLaunch(firstID, now: Date(timeIntervalSince1970: 1_100))
        staleState.updateAccount(firstID, usedUnits: 5)
        outputContinuation?.resume(returning: PoolDashboardUsageSyncFlowCoordinator.Output(
            state: staleState,
            viewState: PoolDashboardViewState()
        ))

        let staleOutcome = await syncTask.value

        #expect(staleOutcome?.status == .staleDiscard)
        #expect(staleOutcome?.stateApplied == false)
        #expect(model.state.activeAccountID == secondID)
        #expect(model.state.accounts.first(where: { $0.id == firstID })?.usedUnits == 40)
        #expect(!store.savedSnapshots.contains { $0.accounts.first?.usedUnits == 5 })
    }

    @Test
    func switchAccountMarksOfficialAccountActiveAfterSuccessfulSwitch() async {
        let store = SpyStore()
        let account = AgentAccount(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            name: "official@example.com",
            usedUnits: 20,
            quota: 100,
            apiToken: "access-token",
            credentialType: .chatGPTOAuth,
            chatGPTAccountID: "user-official"
        )
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: AccountPoolState(accounts: [account], mode: .manual),
            officialSwitchRunner: { request in
                #expect(request.account.id == account.id)
                return .success("official switched")
            },
            relaySwitchRunner: { _ in
                Issue.record("relay runner must not be used for an OAuth account")
                return .failure("wrong runner")
            }
        )

        await model.switchAccount(account.id)

        #expect(model.state.activeAccountID == account.id)
        #expect(model.lastSwitchMessage == "official switched")
        #expect(store.savedSnapshots.count == 1)
    }

    @Test
    func switchAccountUsesRelayRunnerForRelayAccount() async {
        let relayID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let account = AgentAccount(
            id: relayID,
            name: "relay",
            usedUnits: 0,
            quota: 100,
            apiToken: "relay-key",
            credentialType: .relayAPIKey,
            relayProviderID: "mirror",
            relayProviderName: "mirror",
            relayBaseURL: "https://relay.example.test/api/codex",
            relayWireAPI: "responses",
            relayRequiresOpenAIAuth: true,
            isUsageSyncExcluded: true,
            usageSyncError: AgentAccount.relayUsageSyncUnavailableReason
        )
        let model = AppPoolRuntimeModel(
            initialState: AccountPoolState(accounts: [account], mode: .manual),
            officialSwitchRunner: { _ in
                Issue.record("official runner must not be used for relay account")
                return .failure("wrong runner")
            },
            relaySwitchRunner: { request in
                #expect(request.accountID == relayID)
                #expect(request.apiKey == "relay-key")
                return .success("relay switched")
            }
        )

        await model.switchAccount(relayID)

        #expect(model.state.activeAccountID == relayID)
        #expect(model.lastSwitchMessage == "relay switched")
    }

    @Test
    func switchAccountIgnoresAlreadyActiveAccountWithoutSaving() async {
        let store = SpyStore()
        let initialState = makeTwoAccountState()
        let activeID = initialState.activeAccountID!
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: initialState,
            widgetPublisher: { _ in },
            officialSwitchRunner: { _ in
                .success("already active")
            },
            relaySwitchRunner: { _ in
                Issue.record("relay runner must not be used for an OAuth account")
                return .failure("wrong runner")
            }
        )

        await model.switchAccount(activeID)

        #expect(model.state.snapshot == initialState.snapshot)
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test
    func bootstrapStartsMenuBarClockWithoutPersistingOrPublishingOnTicks() async {
        let store = SpyStore()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var nowOffset: TimeInterval = 0
        var publishedSnapshots: [AccountPoolSnapshot] = []
        var state = makeState(name: "clock@example.com")
        state.setAutoSyncEnabled(false)
        state.markUsageSynced(at: baseDate)
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: state,
            menuBarClockIntervalNanoseconds: 1_000_000,
            menuBarNowProvider: {
                let date = baseDate.addingTimeInterval(nowOffset)
                nowOffset += 20
                return date
            },
            widgetPublisher: { snapshot in
                publishedSnapshots.append(snapshot)
            }
        )
        let initialMenuBarNow = model.menuBarNow
        let initialTitle = model.menuBarSnapshot.title
        let (ticks, tickContinuation) = AsyncStream<Date>.makeStream()
        var cancellables = Set<AnyCancellable>()
        model.$menuBarNow
            .dropFirst()
            .sink { date in tickContinuation.yield(date) }
            .store(in: &cancellables)

        model.bootstrapIfNeeded()

        let tickedDate = await nextValue(from: ticks)

        #expect(tickedDate != nil)
        #expect(model.menuBarNow != initialMenuBarNow)
        #expect(model.menuBarSnapshot.title != initialTitle)
        #expect(store.savedSnapshots.isEmpty)
        #expect(publishedSnapshots.count == 1)
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

        let didStart: Void? = await nextValue(from: syncStarted)
        #expect(didStart != nil)
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

        let didStart: Void? = await nextValue(from: syncStarted)
        #expect(didStart != nil)
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

    @Test
    func syncNowPublishesErrorOutcomeWithoutChangingState() async {
        let store = SpyStore()
        let initialState = makeState(name: "error-stable@example.com")
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: initialState,
            syncRunner: { state, _ in
                var mutatedState = state
                mutatedState.updateAccount(
                    state.accounts[0].id,
                    name: "should-not-apply@example.com",
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

        let outcome = await model.syncNow()

        #expect(outcome?.previousState.snapshot == initialState.snapshot)
        #expect(outcome?.previousSyncError == nil)
        #expect(outcome?.status == .failure)
        #expect(outcome?.syncError == "offline")
        #expect(outcome?.stateApplied == false)
        #expect(outcome?.resultingState.snapshot == initialState.snapshot)
        #expect(model.lastSyncOutcome?.id == outcome?.id)
        #expect(model.lastSyncError == "offline")
        #expect(model.state.accounts.first?.name == "error-stable@example.com")
        #expect(store.savedSnapshots.isEmpty)
    }

    @Test
    func syncNowOutcomeIncludesPreviousStateAndPreviousErrorWhenRecovered() async {
        let store = SpyStore()
        let initialState = makeState(name: "recovering@example.com")
        var syncCallCount = 0
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: initialState,
            syncRunner: { state, _ in
                syncCallCount += 1
                var nextViewState = PoolDashboardViewState()
                if syncCallCount == 1 {
                    nextViewState.syncError = "offline"
                    return PoolDashboardUsageSyncFlowCoordinator.Output(
                        state: state,
                        viewState: nextViewState
                    )
                }

                var next = state
                next.updateAccount(state.accounts[0].id, usedUnits: 8)
                return PoolDashboardUsageSyncFlowCoordinator.Output(
                    state: next,
                    viewState: nextViewState
                )
            }
        )

        _ = await model.syncNow()
        let outcome = await model.syncNow()

        #expect(outcome?.previousState.snapshot == initialState.snapshot)
        #expect(outcome?.previousSyncError == "offline")
        #expect(outcome?.status == .success)
        #expect(outcome?.syncError == nil)
        #expect(outcome?.stateApplied == true)
        #expect(outcome?.resultingState.accounts.first?.usedUnits == 8)
        #expect(model.lastSyncError == nil)
    }

    @Test
    func cancelSyncWithErrorPublishesTimeoutInvalidatesStaleOutputAndAllowsRetry() async {
        let store = SpyStore()
        let initialState = makeState(name: "timeout@example.com")
        var syncCallCount = 0
        var firstSyncContinuation: CheckedContinuation<PoolDashboardUsageSyncFlowCoordinator.Output, Never>?
        let (syncStarted, syncStartedContinuation) = AsyncStream<Void>.makeStream()
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: initialState,
            syncRunner: { state, _ in
                syncCallCount += 1
                if syncCallCount == 1 {
                    return await withCheckedContinuation { continuation in
                        firstSyncContinuation = continuation
                        syncStartedContinuation.yield(())
                    }
                }

                var next = state
                next.updateAccount(state.accounts[0].id, usedUnits: 12)
                return PoolDashboardUsageSyncFlowCoordinator.Output(
                    state: next,
                    viewState: PoolDashboardViewState()
                )
            }
        )

        let firstSyncTask = Task {
            await model.syncNow()
        }
        let didStart: Void? = await nextValue(from: syncStarted)
        #expect(didStart != nil)

        let timeoutOutcome = model.cancelSyncWithError("timeout")

        #expect(timeoutOutcome?.syncError == "timeout")
        #expect(timeoutOutcome?.stateApplied == false)
        #expect(model.isSyncingUsage == false)
        #expect(model.lastSyncError == "timeout")
        #expect(model.lastSyncOutcome?.id == timeoutOutcome?.id)

        var staleState = initialState
        staleState.updateAccount(initialState.accounts[0].id, usedUnits: 99)
        firstSyncContinuation?.resume(returning: PoolDashboardUsageSyncFlowCoordinator.Output(
            state: staleState,
            viewState: PoolDashboardViewState()
        ))
        let staleOutcome = await firstSyncTask.value

        #expect(staleOutcome?.status == .staleDiscard)
        #expect(staleOutcome?.stateApplied == false)
        #expect(model.state.accounts.first?.usedUnits == initialState.accounts.first?.usedUnits)
        #expect(store.savedSnapshots.isEmpty)

        let retryOutcome = await model.syncNow()

        #expect(retryOutcome?.status == .success)
        #expect(retryOutcome?.stateApplied == true)
        #expect(retryOutcome?.previousSyncError == "timeout")
        #expect(model.lastSyncError == nil)
        #expect(model.state.accounts.first?.usedUnits == 12)
    }

    @Test
    func cancelSyncWithErrorDoesNotOverwriteCompletedSyncWhenNoSyncIsActive() async {
        let store = SpyStore()
        let initialState = makeState(name: "complete@example.com")
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: initialState,
            syncRunner: { state, _ in
                var next = state
                next.updateAccount(state.accounts[0].id, usedUnits: 22)
                return PoolDashboardUsageSyncFlowCoordinator.Output(
                    state: next,
                    viewState: PoolDashboardViewState()
                )
            }
        )

        let successOutcome = await model.syncNow()
        let completedOutcomeID = model.lastSyncOutcome?.id
        let ignoredTimeoutOutcome: AppPoolRuntimeModel.SyncOutcome? = model.cancelSyncWithError("timeout")

        #expect(successOutcome?.stateApplied == true)
        #expect(ignoredTimeoutOutcome == nil)
        #expect(model.lastSyncError == nil)
        #expect(model.lastSyncOutcome?.id == completedOutcomeID)
        #expect(model.state.accounts.first?.usedUnits == 22)
    }

    @Test
    func syncNowWithTimeoutPublishesTimeoutInvalidatesHungSyncAndAllowsRetry() async {
        let store = SpyStore()
        let initialState = makeState(name: "timeout-api@example.com")
        var syncCallCount = 0
        var firstSyncContinuation: CheckedContinuation<PoolDashboardUsageSyncFlowCoordinator.Output, Never>?
        let (syncStarted, syncStartedContinuation) = AsyncStream<Void>.makeStream()
        let (outcomes, outcomeContinuation) = AsyncStream<AppPoolRuntimeModel.SyncOutcome>.makeStream()
        var cancellables = Set<AnyCancellable>()
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: initialState,
            syncRunner: { state, _ in
                syncCallCount += 1
                if syncCallCount == 1 {
                    return await withCheckedContinuation { continuation in
                        firstSyncContinuation = continuation
                        syncStartedContinuation.yield(())
                    }
                }

                var next = state
                next.updateAccount(state.accounts[0].id, usedUnits: 14)
                return PoolDashboardUsageSyncFlowCoordinator.Output(
                    state: next,
                    viewState: PoolDashboardViewState()
                )
            }
        )
        model.$lastSyncOutcome
            .compactMap { $0 }
            .sink { outcome in outcomeContinuation.yield(outcome) }
            .store(in: &cancellables)

        let timeoutOutcome = await model.syncNowWithTimeout(
            timeoutNanoseconds: 1_000_000,
            timeoutErrorMessage: "timeout"
        )
        let didStart: Void? = await nextValue(from: syncStarted)
        #expect(didStart != nil)

        #expect(timeoutOutcome?.status == .timeout)
        #expect(timeoutOutcome?.syncError == "timeout")
        #expect(timeoutOutcome?.stateApplied == false)
        #expect(model.isSyncingUsage == false)
        #expect(model.lastSyncError == "timeout")

        var staleState = initialState
        staleState.updateAccount(initialState.accounts[0].id, usedUnits: 99)
        firstSyncContinuation?.resume(returning: PoolDashboardUsageSyncFlowCoordinator.Output(
            state: staleState,
            viewState: PoolDashboardViewState()
        ))
        let staleOutcome = await nextOutcome(from: outcomes, matching: .staleDiscard)

        #expect(staleOutcome?.stateApplied == false)
        #expect(model.lastSyncError == "timeout")
        #expect(model.state.accounts.first?.usedUnits == initialState.accounts.first?.usedUnits)
        #expect(store.savedSnapshots.isEmpty)

        let retryOutcome = await model.syncNowWithTimeout(
            timeoutNanoseconds: 1_000_000_000,
            timeoutErrorMessage: "timeout"
        )

        #expect(retryOutcome?.status == .success)
        #expect(retryOutcome?.previousSyncError == "timeout")
        #expect(model.lastSyncError == nil)
        #expect(model.state.accounts.first?.usedUnits == 14)
    }

    @Test
    func syncNowWithTimeoutReturnsSuccessfulOutcomeWhenTimeoutTaskIsCancelled() async {
        let store = SpyStore()
        let initialState = makeState(name: "fast-success@example.com")
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: initialState,
            syncRunner: { state, _ in
                var next = state
                next.updateAccount(state.accounts[0].id, usedUnits: 18)
                return PoolDashboardUsageSyncFlowCoordinator.Output(
                    state: next,
                    viewState: PoolDashboardViewState()
                )
            }
        )

        let outcome = await model.syncNowWithTimeout(
            timeoutNanoseconds: 1_000_000_000,
            timeoutErrorMessage: "timeout"
        )

        #expect(outcome?.status == .success)
        #expect(outcome?.stateApplied == true)
        #expect(outcome?.syncError == nil)
        #expect(model.lastSyncError == nil)
        #expect(model.state.accounts.first?.usedUnits == 18)
    }

    @Test
    func syncNowWithTimeoutCancellationClearsHungSyncAndAllowsRetry() async {
        let store = SpyStore()
        let initialState = makeState(name: "cancel-timeout@example.com")
        var syncCallCount = 0
        var firstSyncContinuation: CheckedContinuation<PoolDashboardUsageSyncFlowCoordinator.Output, Never>?
        let (syncStarted, syncStartedContinuation) = AsyncStream<Void>.makeStream()
        let (outcomes, outcomeContinuation) = AsyncStream<AppPoolRuntimeModel.SyncOutcome>.makeStream()
        var cancellables = Set<AnyCancellable>()
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: initialState,
            syncRunner: { state, _ in
                syncCallCount += 1
                if syncCallCount == 1 {
                    syncStartedContinuation.yield(())
                    return await withCheckedContinuation { continuation in
                        firstSyncContinuation = continuation
                    }
                }

                var next = state
                next.updateAccount(state.accounts[0].id, usedUnits: 24)
                return PoolDashboardUsageSyncFlowCoordinator.Output(
                    state: next,
                    viewState: PoolDashboardViewState()
                )
            }
        )
        model.$lastSyncOutcome
            .compactMap { $0 }
            .sink { outcome in outcomeContinuation.yield(outcome) }
            .store(in: &cancellables)

        let syncTask = Task {
            await model.syncNowWithTimeout(
                timeoutNanoseconds: 1_000_000_000,
                timeoutErrorMessage: "timeout"
            )
        }
        let didStart: Void? = await nextValue(from: syncStarted)
        #expect(didStart != nil)

        syncTask.cancel()
        let cancelledOutcome = await nextValue(from: AsyncStream { continuation in
            Task {
                continuation.yield(await syncTask.value)
                continuation.finish()
            }
        }, timeoutNanoseconds: 100_000_000)

        #expect(cancelledOutcome != nil)
        let flattenedOutcome = cancelledOutcome ?? nil
        #expect(flattenedOutcome == nil)
        #expect(model.isSyncingUsage == false)

        let retryOutcome = await model.syncNowWithTimeout(
            timeoutNanoseconds: 1_000_000_000,
            timeoutErrorMessage: "timeout"
        )

        #expect(syncCallCount == 2)
        #expect(retryOutcome?.status == .success)
        #expect(model.state.accounts.first?.usedUnits == 24)

        var staleState = initialState
        staleState.updateAccount(initialState.accounts[0].id, usedUnits: 99)
        firstSyncContinuation?.resume(returning: PoolDashboardUsageSyncFlowCoordinator.Output(
            state: staleState,
            viewState: PoolDashboardViewState()
        ))
        let staleOutcome = await nextOutcome(from: outcomes, matching: .staleDiscard)

        #expect(staleOutcome?.stateApplied == false)
        #expect(model.state.accounts.first?.usedUnits == 24)
    }

    @Test
    func stopAutoSyncClearsHungActiveSyncAndAllowsRetry() async {
        let store = SpyStore()
        var state = makeState(name: "stop-auto@example.com")
        state.setAutoSyncEnabled(true)
        state.setAutoSyncIntervalSeconds(5)
        var syncCallCount = 0
        var firstSyncContinuation: CheckedContinuation<PoolDashboardUsageSyncFlowCoordinator.Output, Never>?
        let (syncStarted, syncStartedContinuation) = AsyncStream<Void>.makeStream()
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: state,
            syncTimeoutNanoseconds: 1_000_000_000,
            syncRunner: { state, _ in
                syncCallCount += 1
                if syncCallCount == 1 {
                    return await withCheckedContinuation { continuation in
                        firstSyncContinuation = continuation
                        syncStartedContinuation.yield(())
                    }
                }

                var next = state
                next.updateAccount(state.accounts[0].id, usedUnits: 16)
                return PoolDashboardUsageSyncFlowCoordinator.Output(
                    state: next,
                    viewState: PoolDashboardViewState()
                )
            }
        )

        model.startAutoSyncIfNeeded()
        let didStart: Void? = await nextValue(from: syncStarted)
        #expect(didStart != nil)
        #expect(model.isSyncingUsage == true)

        model.stopAutoSync()

        #expect(model.isSyncingUsage == false)

        let retryOutcome = await model.syncNowWithTimeout(
            timeoutNanoseconds: 1_000_000_000,
            timeoutErrorMessage: "timeout"
        )

        #expect(retryOutcome?.status == .success)
        #expect(model.state.accounts.first?.usedUnits == 16)

        var staleState = state
        staleState.updateAccount(state.accounts[0].id, usedUnits: 99)
        firstSyncContinuation?.resume(returning: PoolDashboardUsageSyncFlowCoordinator.Output(
            state: staleState,
            viewState: PoolDashboardViewState()
        ))
    }

    @Test
    func autoSyncUsesTimeoutAwareRuntimeSync() async {
        let store = SpyStore()
        var state = makeState(name: "auto-timeout@example.com")
        state.setAutoSyncEnabled(true)
        state.setAutoSyncIntervalSeconds(5)
        var syncContinuation: CheckedContinuation<PoolDashboardUsageSyncFlowCoordinator.Output, Never>?
        let (syncStarted, syncStartedContinuation) = AsyncStream<Void>.makeStream()
        let (outcomes, outcomeContinuation) = AsyncStream<AppPoolRuntimeModel.SyncOutcome>.makeStream()
        var cancellables = Set<AnyCancellable>()
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: state,
            syncTimeoutNanoseconds: 1_000_000,
            syncRunner: { state, _ in
                await withCheckedContinuation { continuation in
                    syncContinuation = continuation
                    syncStartedContinuation.yield(())
                }
            }
        )
        model.$lastSyncOutcome
            .compactMap { $0 }
            .sink { outcome in outcomeContinuation.yield(outcome) }
            .store(in: &cancellables)

        model.startAutoSyncIfNeeded()
        let didStart: Void? = await nextValue(from: syncStarted)
        #expect(didStart != nil)
        let timeoutOutcome = await nextOutcome(from: outcomes, matching: .timeout)
        model.stopAutoSync()

        #expect(timeoutOutcome?.status == .timeout)
        #expect(model.isSyncingUsage == false)
        syncContinuation?.resume(returning: PoolDashboardUsageSyncFlowCoordinator.Output(
            state: state,
            viewState: PoolDashboardViewState()
        ))
    }
}
