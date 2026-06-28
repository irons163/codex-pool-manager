import Combine
import Foundation

private let appPoolRuntimeDefaultSyncTimeoutNanoseconds: UInt64 = 45_000_000_000

enum AppPoolRuntimeSyncOutcomeStatus: Sendable {
    case success
    case failure
    case timeout
    case staleDiscard
}

struct AppPoolRuntimeSyncOutcome: Identifiable {
    let id: UUID
    let status: AppPoolRuntimeSyncOutcomeStatus
    let previousState: AccountPoolState
    let previousSyncError: String?
    let outputViewState: PoolDashboardViewState
    let syncError: String?
    let stateApplied: Bool
    let resultingState: AccountPoolState
}

@MainActor
final class AppPoolRuntimeModel: ObservableObject {
    typealias SyncOutcome = AppPoolRuntimeSyncOutcome

    private enum SyncOrigin {
        case manual
        case autoSync
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
    private let syncTimeoutNanoseconds: UInt64
    private var stateRevision = 0
    private var autoSyncTask: Task<Void, Never>?
    private var activeSyncID: UUID?
    private var activeSyncOrigin: SyncOrigin?
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
        syncTimeoutNanoseconds: UInt64 = appPoolRuntimeDefaultSyncTimeoutNanoseconds,
        widgetPublisher: @escaping WidgetPublisher = { WidgetBridgePublisher.publish(from: $0) },
        syncRunner: @escaping SyncRunner = { state, viewState in
            await PoolDashboardUsageSyncFlowCoordinator()
                .syncCodexUsage(from: state, viewState: viewState)
        }
    ) {
        self.init(
            store: AppRuntimeStorage.accountPoolStore,
            initialState: initialState,
            syncTimeoutNanoseconds: syncTimeoutNanoseconds,
            widgetPublisher: widgetPublisher,
            syncRunner: syncRunner
        )
    }

    init(
        store: AccountPoolStoring,
        initialState: AccountPoolState? = nil,
        syncTimeoutNanoseconds: UInt64 = appPoolRuntimeDefaultSyncTimeoutNanoseconds,
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
        self.syncTimeoutNanoseconds = syncTimeoutNanoseconds
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
                await self?.syncNowWithTimeout(origin: .autoSync)
                if Task.isCancelled { break }
                let sleepNanoseconds = self?.autoSyncSleepNanoseconds() ?? Self.minimumAutoSyncSleepNanoseconds
                try? await Task.sleep(nanoseconds: sleepNanoseconds)
            }
        }
    }

    func stopAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
        cancelActiveSyncSilently(origin: .autoSync)
    }

    func restartAutoSyncIfNeeded() {
        stopAutoSync()
        startAutoSyncIfNeeded()
    }

    @discardableResult
    func syncNow() async -> SyncOutcome? {
        await syncNow(origin: .manual)
    }

    @discardableResult
    private func syncNow(origin: SyncOrigin) async -> SyncOutcome? {
        await syncNow(origin: origin, syncID: UUID())
    }

    @discardableResult
    private func syncNow(origin: SyncOrigin, syncID: UUID) async -> SyncOutcome? {
        guard !Task.isCancelled else { return nil }
        guard !isSyncingUsage else { return nil }

        activeSyncID = syncID
        activeSyncOrigin = origin
        isSyncingUsage = true
        defer {
            if activeSyncID == syncID {
                activeSyncID = nil
                activeSyncOrigin = nil
                isSyncingUsage = false
            }
        }

        let previousState = state
        let previousSyncError = lastSyncError
        let syncRevision = stateRevision
        let output = await syncRunner(state, PoolDashboardViewState())
        let syncError = Self.normalizedSyncError(output.viewState.syncError)
        guard syncRevision == stateRevision else {
            return publishSyncOutcome(
                status: .staleDiscard,
                previousState: previousState,
                previousSyncError: previousSyncError,
                outputViewState: output.viewState,
                syncError: nil,
                stateApplied: false,
                resultingState: state
            )
        }

        if let syncError, !syncError.isEmpty {
            lastSyncError = syncError
            return publishSyncOutcome(
                status: .failure,
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
            status: .success,
            previousState: previousState,
            previousSyncError: previousSyncError,
            outputViewState: output.viewState,
            syncError: nil,
            stateApplied: true,
            resultingState: state
        )
    }

    func cancelSyncWithError(_ message: String) -> SyncOutcome? {
        guard activeSyncID != nil || isSyncingUsage else {
            return nil
        }

        let previousState = state
        let previousSyncError = lastSyncError
        var outputViewState = PoolDashboardViewState()
        outputViewState.syncError = message

        stateRevision += 1
        activeSyncID = nil
        activeSyncOrigin = nil
        isSyncingUsage = false
        lastSyncError = message
        return publishSyncOutcome(
            status: .timeout,
            previousState: previousState,
            previousSyncError: previousSyncError,
            outputViewState: outputViewState,
            syncError: message,
            stateApplied: false,
            resultingState: state
        )
    }

    @discardableResult
    func syncNowWithTimeout(
        timeoutNanoseconds: UInt64? = nil,
        timeoutErrorMessage: String? = nil
    ) async -> SyncOutcome? {
        await syncNowWithTimeout(
            timeoutNanoseconds: timeoutNanoseconds,
            timeoutErrorMessage: timeoutErrorMessage,
            origin: .manual
        )
    }

    @discardableResult
    private func syncNowWithTimeout(
        timeoutNanoseconds: UInt64? = nil,
        timeoutErrorMessage: String? = nil,
        origin: SyncOrigin
    ) async -> SyncOutcome? {
        let timeoutNanoseconds = timeoutNanoseconds ?? syncTimeoutNanoseconds
        let timeoutErrorMessage = timeoutErrorMessage ?? Self.defaultSyncTimeoutErrorMessage()
        let syncID = UUID()
        let syncTask = Task<SyncOutcome?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.syncNow(origin: origin, syncID: syncID)
        }
        let timeoutTask = Task<SyncOutcome?, Never> { [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
            } catch {
                return nil
            }

            guard !Task.isCancelled else {
                return nil
            }

            guard let self else { return nil }
            return self.cancelSyncWithError(timeoutErrorMessage)
        }
        let resolver = SyncOutcomeRaceResolver()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                Task {
                    let shouldStartWaiters = await resolver.register(continuation)
                    guard shouldStartWaiters else { return }

                    Task {
                        let outcome = await syncTask.value
                        timeoutTask.cancel()
                        await resolver.resume(outcome)
                    }
                    Task {
                        let outcome = await timeoutTask.value
                        syncTask.cancel()
                        await resolver.resume(outcome)
                    }
                }
            }
        } onCancel: {
            syncTask.cancel()
            timeoutTask.cancel()
            Task {
                await self.cancelActiveSyncSilently(origin: origin, syncID: syncID)
                await resolver.cancel()
            }
        }
    }

    private func cancelActiveSyncSilently(origin: SyncOrigin) {
        cancelActiveSyncSilently(origin: origin, syncID: nil)
    }

    private func cancelActiveSyncSilently(origin: SyncOrigin, syncID: UUID?) {
        guard activeSyncID != nil || isSyncingUsage else { return }
        guard activeSyncOrigin == origin else { return }
        if let syncID {
            guard activeSyncID == syncID else { return }
        }

        stateRevision += 1
        activeSyncID = nil
        activeSyncOrigin = nil
        isSyncingUsage = false
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
        status: AppPoolRuntimeSyncOutcomeStatus,
        previousState: AccountPoolState,
        previousSyncError: String?,
        outputViewState: PoolDashboardViewState,
        syncError: String?,
        stateApplied: Bool,
        resultingState: AccountPoolState
    ) -> SyncOutcome {
        let outcome = SyncOutcome(
            id: UUID(),
            status: status,
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

    static let defaultSyncTimeoutNanoseconds: UInt64 = appPoolRuntimeDefaultSyncTimeoutNanoseconds
    private static let minimumAutoSyncSleepNanoseconds: UInt64 = 5_000_000_000

    private func autoSyncSleepNanoseconds() -> UInt64 {
        let clampedSeconds = max(5, state.autoSyncIntervalSeconds)
        return UInt64(clampedSeconds * 1_000_000_000)
    }

    private static func defaultSyncTimeoutErrorMessage() -> String {
        L10n.text(
            "sync.failure.with_description_format",
            L10n.text("sync.failure.prefix"),
            L10n.text("usage.sync.error.timeout")
        )
    }
}

private actor SyncOutcomeRaceResolver {
    private var didResume = false
    private var didCancel = false
    private var nilResultCount = 0
    private var continuation: CheckedContinuation<AppPoolRuntimeModel.SyncOutcome?, Never>?

    func register(
        _ continuation: CheckedContinuation<AppPoolRuntimeModel.SyncOutcome?, Never>
    ) -> Bool {
        guard !didResume else {
            continuation.resume(returning: nil)
            return false
        }

        self.continuation = continuation
        if didCancel {
            resumeNil()
            return false
        }

        return true
    }

    func resume(_ outcome: AppPoolRuntimeModel.SyncOutcome?) {
        guard !didResume else { return }
        guard let outcome else {
            nilResultCount += 1
            if nilResultCount == 2 {
                resumeNil()
            }
            return
        }

        resume(outcome)
    }

    func cancel() {
        guard !didResume else { return }
        didCancel = true
        if continuation != nil {
            resumeNil()
        }
    }

    private func resume(_ outcome: AppPoolRuntimeModel.SyncOutcome) {
        didResume = true
        continuation?.resume(returning: outcome)
        continuation = nil
    }

    private func resumeNil() {
        didResume = true
        continuation?.resume(returning: nil)
        continuation = nil
    }
}
