import Combine
import Foundation

@MainActor
final class AppPoolRuntimeModel: ObservableObject {
    typealias SyncRunner = @MainActor (
        _ state: AccountPoolState,
        _ viewState: PoolDashboardViewState
    ) async -> PoolDashboardUsageSyncFlowCoordinator.Output
    typealias WidgetPublisher = @MainActor (_ snapshot: AccountPoolSnapshot) -> Void

    @Published private(set) var state: AccountPoolState
    @Published private(set) var isSyncingUsage = false
    @Published private(set) var lastSyncError: String?

    private let store: AccountPoolStoring
    private let syncRunner: SyncRunner
    private let widgetPublisher: WidgetPublisher
    private var stateRevision = 0

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
        self.state = initialState ?? AccountPoolState(accounts: [])
        self.widgetPublisher = widgetPublisher
        self.syncRunner = syncRunner
    }

    func load() {
        if let snapshot = store.load() {
            state = AccountPoolState(snapshot: snapshot)
            stateRevision += 1
        }
        publishWidgetSnapshot()
    }

    func replaceStateFromDashboard(_ nextState: AccountPoolState) {
        state = nextState
        stateRevision += 1
        saveAndPublish()
    }

    func syncNow() async {
        guard !isSyncingUsage else { return }

        isSyncingUsage = true
        defer { isSyncingUsage = false }

        let syncRevision = stateRevision
        let output = await syncRunner(state, PoolDashboardViewState())
        guard syncRevision == stateRevision else { return }

        let syncError = output.viewState.syncError?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let syncError, !syncError.isEmpty {
            lastSyncError = syncError
            return
        }

        state = output.state
        stateRevision += 1
        lastSyncError = nil
        saveAndPublish()
    }

    private func saveAndPublish() {
        store.save(state.snapshot)
        publishWidgetSnapshot()
    }

    private func publishWidgetSnapshot() {
        widgetPublisher(state.snapshot)
    }
}
