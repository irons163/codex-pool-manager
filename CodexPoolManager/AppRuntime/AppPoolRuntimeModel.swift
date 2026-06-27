import Combine
import Foundation

@MainActor
final class AppPoolRuntimeModel: ObservableObject {
    struct SyncOutcome: Identifiable {
        let id: UUID
        let previousState: AccountPoolState
        let previousSyncError: String?
        let outputViewState: PoolDashboardViewState
        let syncError: String?
        let stateApplied: Bool
        let resultingState: AccountPoolState
    }

    typealias SyncRunner = @MainActor (
        _ state: AccountPoolState,
        _ viewState: PoolDashboardViewState
    ) async -> PoolDashboardUsageSyncFlowCoordinator.Output
    typealias WidgetPublisher = @MainActor (_ snapshot: AccountPoolSnapshot) -> Void

    @Published private(set) var state: AccountPoolState
    @Published private(set) var isSyncingUsage = false
    @Published private(set) var lastSyncError: String?
    @Published private(set) var lastSyncOutcome: SyncOutcome?

    private let store: AccountPoolStoring
    private let syncRunner: SyncRunner
    private let widgetPublisher: WidgetPublisher
    private var stateRevision = 0
    private var autoSyncTask: Task<Void, Never>?
    private var didBootstrap = false
    private var didLoadFromStore = false

    var menuBarSnapshot: MenuBarDashboardSnapshot {
        MenuBarDashboardPresenter.makeSnapshot(
            from: state,
            isSyncing: isSyncingUsage,
            lastSyncError: lastSyncError
        )
    }

    convenience init(
        initialState: AccountPoolState? = nil,
        widgetPublisher: @escaping WidgetPublisher = { WidgetBridgePublisher.publish(from: $0) },
        syncRunner: @escaping SyncRunner = { state, viewState in
            await PoolDashboardUsageSyncFlowCoordinator()
                .syncCodexUsage(from: state, viewState: viewState)
        }
    ) {
        self.init(
            store: AppRuntimeStorage.accountPoolStore,
            initialState: initialState,
            widgetPublisher: widgetPublisher,
            syncRunner: syncRunner
        )
    }

    init(
        store: AccountPoolStoring,
        initialState: AccountPoolState? = nil,
        widgetPublisher: @escaping WidgetPublisher = { WidgetBridgePublisher.publish(from: $0) },
        syncRunner: @escaping SyncRunner = { state, viewState in
            await PoolDashboardUsageSyncFlowCoordinator()
                .syncCodexUsage(from: state, viewState: viewState)
        }
    ) {
        self.store = store
        if let initialState {
            self.state = initialState
            self.didLoadFromStore = true
        } else if let snapshot = store.load() {
            self.state = AccountPoolState(snapshot: snapshot)
            self.didLoadFromStore = true
            self.stateRevision = 1
        } else {
            self.state = AccountPoolState(accounts: [])
            self.didLoadFromStore = true
        }
        self.widgetPublisher = widgetPublisher
        self.syncRunner = syncRunner
    }

    deinit {
        autoSyncTask?.cancel()
    }

    func load() {
        if let snapshot = store.load() {
            state = AccountPoolState(snapshot: snapshot)
            stateRevision += 1
        }
        didLoadFromStore = true
        publishWidgetSnapshot()
    }

    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        if didLoadFromStore {
            publishWidgetSnapshot()
        } else {
            load()
        }
        startAutoSyncIfNeeded()
    }

    func replaceStateFromDashboard(_ nextState: AccountPoolState) {
        guard state.snapshot != nextState.snapshot else { return }
        state = nextState
        stateRevision += 1
        saveAndPublish()
    }

    func startAutoSyncIfNeeded() {
        guard autoSyncTask == nil else { return }
        guard state.autoSyncEnabled else { return }

        autoSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncNow()
                if Task.isCancelled { break }
                let sleepNanoseconds = self?.autoSyncSleepNanoseconds() ?? Self.minimumAutoSyncSleepNanoseconds
                try? await Task.sleep(nanoseconds: sleepNanoseconds)
            }
        }
    }

    func stopAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
    }

    func restartAutoSyncIfNeeded() {
        stopAutoSync()
        startAutoSyncIfNeeded()
    }

    @discardableResult
    func syncNow() async -> SyncOutcome? {
        guard !isSyncingUsage else { return nil }

        isSyncingUsage = true
        defer { isSyncingUsage = false }

        let previousState = state
        let previousSyncError = lastSyncError
        let syncRevision = stateRevision
        let output = await syncRunner(state, PoolDashboardViewState())
        let syncError = Self.normalizedSyncError(output.viewState.syncError)
        guard syncRevision == stateRevision else {
            return publishSyncOutcome(
                previousState: previousState,
                previousSyncError: previousSyncError,
                outputViewState: output.viewState,
                syncError: syncError,
                stateApplied: false,
                resultingState: state
            )
        }

        if let syncError, !syncError.isEmpty {
            lastSyncError = syncError
            return publishSyncOutcome(
                previousState: previousState,
                previousSyncError: previousSyncError,
                outputViewState: output.viewState,
                syncError: syncError,
                stateApplied: false,
                resultingState: state
            )
        }

        state = output.state
        stateRevision += 1
        lastSyncError = nil
        saveAndPublish()
        return publishSyncOutcome(
            previousState: previousState,
            previousSyncError: previousSyncError,
            outputViewState: output.viewState,
            syncError: nil,
            stateApplied: true,
            resultingState: state
        )
    }

    private func saveAndPublish() {
        store.save(state.snapshot)
        publishWidgetSnapshot()
    }

    private func publishWidgetSnapshot() {
        widgetPublisher(state.snapshot)
    }

    private static func normalizedSyncError(_ syncError: String?) -> String? {
        let trimmed = syncError?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func publishSyncOutcome(
        previousState: AccountPoolState,
        previousSyncError: String?,
        outputViewState: PoolDashboardViewState,
        syncError: String?,
        stateApplied: Bool,
        resultingState: AccountPoolState
    ) -> SyncOutcome {
        let outcome = SyncOutcome(
            id: UUID(),
            previousState: previousState,
            previousSyncError: previousSyncError,
            outputViewState: outputViewState,
            syncError: syncError,
            stateApplied: stateApplied,
            resultingState: resultingState
        )
        lastSyncOutcome = outcome
        return outcome
    }

    private static let minimumAutoSyncSleepNanoseconds: UInt64 = 15_000_000_000

    private func autoSyncSleepNanoseconds() -> UInt64 {
        let clampedSeconds = max(15, state.autoSyncIntervalSeconds)
        return UInt64(clampedSeconds * 1_000_000_000)
    }
}
