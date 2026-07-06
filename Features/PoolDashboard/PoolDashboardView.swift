import Combine
import SwiftUI
import UserNotifications
#if canImport(AppKit)
import AppKit
#endif
#if canImport(Sparkle)
import Sparkle
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

enum DailyUsagePlanEvaluator {
    enum AlertLevel: String {
        case none
        case warning
        case exceeded
    }

    static func plannedLimitPercent(from rawValue: Int) -> Int {
        max(1, rawValue)
    }

    static func plannedTotalPercent(for dayBudgets: [String: Int]) -> Int {
        dayBudgets.values.reduce(0) { partial, value in
            partial + max(0, value)
        }
    }

    static func activeBudgets(
        for dayBudgets: [String: Int],
        availableAccountKeys: Set<String>
    ) -> [String: Int] {
        guard !availableAccountKeys.isEmpty else { return [:] }
        return dayBudgets.filter { accountKey, budget in
            availableAccountKeys.contains(accountKey) && budget > 0
        }
    }

    static func plannedAccountCount(for dayBudgets: [String: Int]) -> Int {
        dayBudgets.values.filter { $0 > 0 }.count
    }

    static func weekdayKey(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1: return "sun"
        case 2: return "mon"
        case 3: return "tue"
        case 4: return "wed"
        case 5: return "thu"
        case 6: return "fri"
        case 7: return "sat"
        default: return "mon"
        }
    }

    static func warningThresholdPercent(from rawValue: Int) -> Int {
        min(99, max(1, rawValue))
    }

    static func remainingBudgetPercent(todayUsedPercent: Int, plannedLimitPercent: Int) -> Int {
        max(0, plannedLimitPercent - todayUsedPercent)
    }

    static func exceededByPercent(todayUsedPercent: Int, plannedLimitPercent: Int) -> Int {
        max(0, todayUsedPercent - plannedLimitPercent)
    }

    static func progressRatio(todayUsedPercent: Int, plannedLimitPercent: Int) -> Double {
        Double(todayUsedPercent) / Double(max(1, plannedLimitPercent))
    }

    static func warningTriggerPercent(
        plannedLimitPercent: Int,
        warningThresholdPercent: Int
    ) -> Int {
        max(1, Int(ceil(Double(plannedLimitPercent) * Double(warningThresholdPercent) / 100.0)))
    }

    static func alertLevel(
        todayUsedPercent: Int,
        plannedLimitPercent: Int,
        warningThresholdPercent: Int
    ) -> AlertLevel {
        if todayUsedPercent > plannedLimitPercent {
            return .exceeded
        }
        let warningTrigger = warningTriggerPercent(
            plannedLimitPercent: plannedLimitPercent,
            warningThresholdPercent: warningThresholdPercent
        )
        if todayUsedPercent >= warningTrigger {
            return .warning
        }
        return .none
    }

    static func shouldNotify(
        isPlanEnabled: Bool,
        isDesktopNotifyEnabled: Bool,
        alertLevel: AlertLevel,
        scopeStorageKey: String,
        todayKey: String,
        notifiedDaysByScopeAndLevel: [String: String]
    ) -> Bool {
        guard isPlanEnabled, isDesktopNotifyEnabled, alertLevel != .none else {
            return false
        }
        return notifiedDaysByScopeAndLevel[notificationScopeLevelKey(scopeStorageKey: scopeStorageKey, alertLevel: alertLevel)] != todayKey
    }

    static func markNotified(
        alertLevel: AlertLevel,
        scopeStorageKey: String,
        todayKey: String,
        notifiedDaysByScopeAndLevel: [String: String]
    ) -> [String: String] {
        var updated = notifiedDaysByScopeAndLevel
        updated[notificationScopeLevelKey(scopeStorageKey: scopeStorageKey, alertLevel: alertLevel)] = todayKey
        return updated
    }

    private static func notificationScopeLevelKey(scopeStorageKey: String, alertLevel: AlertLevel) -> String {
        "\(scopeStorageKey)|\(alertLevel.rawValue)"
    }
}

struct PoolDashboardView: View {
    private struct RuntimeOwnedSnapshotStore: AccountPoolStoring {
        func load() -> AccountPoolSnapshot? { nil }
        func save(_ snapshot: AccountPoolSnapshot) {}
    }

    private enum SyncPolicy {
        static let timeoutNanoseconds: UInt64 = 45_000_000_000
        static let stuckRecoveryNanoseconds: UInt64 = 70_000_000_000
    }
    private enum ResponsiveLayout {
        static let contentHorizontalPadding: CGFloat = 16
        static let dashboardChromeStackBreakpoint: CGFloat = 1_000
        static let workspaceContentStackBreakpoint: CGFloat = 1_000
    }
    private enum WorkspaceDrawerState {
        case collapsed
        case partial
        case expanded

        var isVisible: Bool {
            self != .collapsed
        }

        var symbolName: String {
            switch self {
            case .collapsed:
                return "chevron.right"
            case .partial:
                return "chevron.up"
            case .expanded:
                return "chevron.down"
            }
        }

        var actionTitleKey: String {
            switch self {
            case .collapsed:
                return "drawer.expand"
            case .partial:
                return "drawer.expand_full"
            case .expanded:
                return "drawer.collapse"
            }
        }

        func next() -> WorkspaceDrawerState {
            switch self {
            case .collapsed:
                return .partial
            case .partial:
                return .expanded
            case .expanded:
                return .collapsed
            }
        }
    }
    private enum AuthMethod: String, CaseIterable, Identifiable {
        case oauth
        case relayAPIKey

        var id: String { rawValue }

        var title: String {
            switch self {
            case .oauth: L10n.text("auth.method.oauth")
            case .relayAPIKey: L10n.text("auth.method.relay_api_key")
            }
        }

        var subtitle: String {
            switch self {
            case .oauth: L10n.text("auth.method.oauth_hint")
            case .relayAPIKey: L10n.text("auth.method.relay_api_key_hint")
            }
        }

        var symbolName: String {
            switch self {
            case .oauth: "person.badge.key"
            case .relayAPIKey: "key.horizontal"
            }
        }
    }

    private static let codexAuthBookmarkKey = "codex_auth_json_bookmark"
    private static let defaultOAuthClientID = OAuthClientConfiguration.defaultClientID
    private static let productionSnapshotKey = "account_pool_snapshot"
    private static let productionTokenKey = "account_pool_tokens"
    private static let developerSnapshotKey = "account_pool_snapshot_developer"
    private static let developerTokenKey = "account_pool_tokens_developer"
    private static let developerMockModeKey = "pool_dashboard.developer.mock_mode"
    private static let switchLaunchTargetKey = "pool_dashboard.switch_launch_target"
    private static let specialResetWatchStateKey = "pool_dashboard.special_reset_watch_state"
    private static let usageAnalyticsStateKey = "pool_dashboard.usage_analytics_state"
    private static let usageAnalyticsMaxStoredRecordsKey = "pool_dashboard.usage_analytics.max_stored_records"
    private static let specialResetGraceMinutesMigrationKey = "pool_dashboard.special_reset_watch_grace_minutes_migrated_v1"
    private static let appUpdateAutoCheckEnabledKey = "pool_dashboard.app_update.auto_check_enabled"
    private static let appUpdateSkippedVersionKey = "pool_dashboard.app_update.skipped_version"
    private static let appUpdateLastCheckedAtKey = "pool_dashboard.app_update.last_checked_at"
    private static let whatsNewLastSeenVersionIDKey = "pool_dashboard.whats_new.last_seen_version_id"
    private static let authenticationMethodKey = "pool_dashboard.authentication.method"
    private static let relayPreserveOfficialAuthKey = "pool_dashboard.relay.preserve_official_auth"
    private struct PendingManualOAuthContext {
        let expectedState: String
        let codeVerifier: String
        let authorizationURL: URL
    }
    private enum SpecialResetKind: String, Codable {
        case weekly
        case fiveHour

        var interval: TimeInterval {
            switch self {
            case .weekly:
                return 7 * 24 * 3_600
            case .fiveHour:
                return 5 * 3_600
            }
        }

        var title: String {
            switch self {
            case .weekly:
                return L10n.text("special_reset.kind.weekly")
            case .fiveHour:
                return L10n.text("special_reset.kind.five_hour")
            }
        }
    }
    private struct SpecialResetRecord: Identifiable, Codable {
        let accountKey: String
        var accountName: String
        var expectedWeeklyResetAt: Date? = nil
        var expectedFiveHourResetAt: Date? = nil
        var lastObservedWeeklyResetAt: Date? = nil
        var lastObservedFiveHourResetAt: Date? = nil
        var lastSeenWeeklyUsagePercent: Int? = nil
        var lastSeenUsedUnits: Int? = nil
        var lastSeenFiveHourUsagePercent: Int? = nil
        var lastSeenAt: Date? = nil

        var id: String { accountKey }
    }
    private struct SpecialResetEvent: Identifiable, Codable {
        let id: UUID
        let detectedAt: Date
        let accountKey: String
        let accountName: String
        let previousWeeklyExpectedAt: Date
        let observedWeeklyNextResetAt: Date
        let previousFiveHourExpectedAt: Date
        let observedFiveHourNextResetAt: Date
    }
    private struct SpecialResetWatchState: Codable {
        var records: [SpecialResetRecord] = []
        var events: [SpecialResetEvent] = []
        var lastEvaluatedAt: Date?
        var lastNotificationAt: Date?
    }
    private struct SpecialResetDetection {
        let accountKey: String
        let accountName: String
        let previousWeeklyExpectedAt: Date
        let observedWeeklyNextResetAt: Date
        let previousFiveHourExpectedAt: Date
        let observedFiveHourNextResetAt: Date
        let detectedAt: Date
    }
    private struct SpecialResetEvaluationOutput {
        let state: SpecialResetWatchState
        let detections: [SpecialResetDetection]
        let shouldNotify: Bool
    }
    private struct UsageAnalyticsStorageNormalizationOutput {
        let normalizedState: UsageAnalyticsState
        let rewrittenRawValue: String?
    }
    private struct DataModeReloadOutput {
        let state: AccountPoolState
        let selectedGroupName: String
    }
    private struct AddAccountHandlingOutput {
        let state: AccountPoolState
        let formState: PoolDashboardFormState
    }
    private struct DeleteGroupHandlingOutput {
        let state: AccountPoolState
        let selectedGroupName: String
        let removedAccountIDs: [UUID]
    }
    private struct DashboardNotificationRequest {
        let key: String
        let title: String
        let body: String
        let minInterval: TimeInterval
    }
    private struct AutomaticSwitchDecision {
        let accountIDToMarkForSwitchLaunch: UUID?
        let notification: DashboardNotificationRequest?
    }
    private enum ManualSwitchRoute {
        case missing
        case relay
        case official(AgentAccount)
    }
    private struct ManualSwitchDecision {
        let accountIDToMarkForSwitchLaunch: UUID?
        let notification: DashboardNotificationRequest?
    }
    private struct RelaySwitchOutcomeDecision {
        let accountIDToMarkForSwitchLaunch: UUID?
        let notification: DashboardNotificationRequest?
    }
    private struct RelaySwitchPreparation {
        let request: PoolDashboardRelayAccountCoordinator.SwitchRequest?
        let diagnosticLog: String
        let requestAccountName: String
        let errorDescription: String?
        let hydratedFromVault: Bool
    }
    private struct AppUpdatePrompt: Identifiable, Equatable {
        let currentVersion: String
        let latestVersion: String
        let release: AppUpdateRelease

        var id: String { latestVersion }
    }
    @AppStorage("oauth_issuer") private var oauthIssuer = "https://auth.openai.com"
    @AppStorage("oauth_client_id") private var oauthClientID = Self.defaultOAuthClientID
    @AppStorage("oauth_scopes") private var oauthScopes = OAuthClientConfiguration.defaultScopes
    @AppStorage("oauth_redirect_uri") private var oauthRedirectURI = OAuthClientConfiguration.defaultRedirectURI
    @AppStorage("oauth_originator") private var oauthOriginator = OAuthClientConfiguration.defaultOriginator
    @AppStorage("oauth_workspace_id") private var oauthWorkspaceID = ""
    @AppStorage(L10n.languageOverrideKey) private var appLanguageOverride = L10n.systemLanguageCode
    @AppStorage(AppAppearancePreference.storageKey) private var appAppearanceOverride = AppAppearancePreference.system.rawValue
    @AppStorage(Self.developerMockModeKey) private var developerMockModeEnabled = false
    @AppStorage(Self.switchLaunchTargetKey) private var switchLaunchTargetRaw = CodexLaunchTarget.defaultPickerTarget.rawValue
    @AppStorage(Self.specialResetWatchStateKey) private var specialResetWatchStateRaw = ""
    @AppStorage(Self.usageAnalyticsStateKey) private var usageAnalyticsStateRaw = ""
    @AppStorage(Self.usageAnalyticsMaxStoredRecordsKey) private var usageAnalyticsMaxStoredRecords = UsageAnalyticsEngine.defaultMaxStoredRecords
    @AppStorage("pool_dashboard.special_reset_watch_enabled") private var specialResetWatchEnabled = true
    @AppStorage("pool_dashboard.special_reset_watch_notify_enabled") private var specialResetWatchNotifyEnabled = true
    @AppStorage("pool_dashboard.special_reset_watch_grace_minutes") private var specialResetWatchGraceMinutes = 1
    @AppStorage(Self.specialResetGraceMinutesMigrationKey) private var didMigrateSpecialResetGraceMinutes = false
    @AppStorage(Self.appUpdateAutoCheckEnabledKey) private var appUpdateAutoCheckEnabled = true
    @AppStorage(Self.appUpdateSkippedVersionKey) private var appUpdateSkippedVersion = ""
    @AppStorage(Self.appUpdateLastCheckedAtKey) private var appUpdateLastCheckedAt = 0.0
    @AppStorage(Self.whatsNewLastSeenVersionIDKey) private var whatsNewLastSeenVersionID = ""
    @AppStorage(Self.authenticationMethodKey) private var selectedAuthMethodRaw = AuthMethod.oauth.rawValue
    @AppStorage(Self.relayPreserveOfficialAuthKey) private var relayPreserveOfficialAuth = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var state: AccountPoolState
    @State private var formState = PoolDashboardFormState()
    @State private var canAddRelayAccount = false
    @State private var resetAllLatch = DestructiveActionLatch()
    @State private var viewState = PoolDashboardViewState()
    @State private var lowUsageAlertPolicy = LowUsageAlertPolicy()
    @State private var localOAuthImportViewModel = LocalOAuthImportViewModel()
    @State private var importingLocalOAuthAccountID: String?
    @State private var sessionAuthorizedAuthFileURL: URL?
    @State private var selectedWorkspace: Workspace = .authentication
    @State private var selectedGroupName: String = AgentAccount.defaultGroupName
    @State private var workspaceDrawerState: WorkspaceDrawerState = .partial
    @State private var isSidebarCollapsed = false
    @State private var isApplyingRuntimeStateUpdate = false
    @State private var lastHandledRuntimeSyncOutcomeID: UUID?
    @State private var themeRenderToken = 0
    @State private var suppressNextSnapshotDrivenSwitch = false
    @State private var usageSyncRunID: UUID?
    @State private var pendingManualOAuthContext: PendingManualOAuthContext?
    @State private var manualOAuthCallbackURL = ""
    @State private var oauthSignInTask: Task<Void, Never>?
    @State private var specialResetWatchState = SpecialResetWatchState()
    @State private var usageAnalyticsState = UsageAnalyticsState()
    @State private var usageAnalyticsStateLoaded = false
    @State private var appUpdateAvailablePrompt: AppUpdatePrompt?
    @State private var appUpdatePrompt: AppUpdatePrompt?
    @State private var whatsNewPrompt: WhatsNewAnnouncement?
    @State private var isCheckingForAppUpdate = false
    @State private var appUpdateStatusMessage: String?
    private let store: AccountPoolStoring
    private let backupFlowCoordinator = PoolDashboardBackupFlowCoordinator()
    private let usageSyncFlowCoordinator = PoolDashboardUsageSyncFlowCoordinator()
    private let oauthSignInFlowCoordinator = PoolDashboardOAuthSignInFlowCoordinator()
    private let relayAccountCoordinator = PoolDashboardRelayAccountCoordinator()
    private let lifecycleFlowCoordinator = PoolDashboardLifecycleFlowCoordinator()
    private let quickActionsFlowCoordinator = PoolDashboardQuickActionsFlowCoordinator()
    private let localAccountsFlowCoordinator = PoolDashboardLocalAccountsFlowCoordinator()
    private let localImportFlowCoordinator = PoolDashboardLocalImportFlowCoordinator()
    private let switchLaunchFlowCoordinator = PoolDashboardSwitchLaunchFlowCoordinator()
    private let usagePresenter = PoolAccountUsagePresenter()
    private let alertPresenter = PoolDashboardAlertPresenter()
    private let viewMutationCoordinator = PoolDashboardViewMutationCoordinator()
    private let asyncStateCoordinator = PoolDashboardAsyncStateCoordinator()
    private let appUpdateService = AppUpdateService()
    private let sparkleUpdateDriver = SparkleUpdateDriver.shared
    private let runtimeModel: AppPoolRuntimeModel?
    private var authFileAccessService: CodexAuthFileAccessService {
        CodexAuthFileAccessService(bookmarkKey: Self.codexAuthBookmarkKey)
    }
    private var accountBindings: PoolDashboardAccountBindingAdapter {
        PoolDashboardAccountBindingAdapter(state: $state)
    }
    private var strategyBindings: PoolDashboardStrategyBindingAdapter {
        PoolDashboardStrategyBindingAdapter(state: $state)
    }

    private var selectedAuthMethod: AuthMethod {
        AuthMethod(rawValue: selectedAuthMethodRaw) ?? .oauth
    }

    private var authMethodBinding: Binding<AuthMethod> {
        Binding(
            get: { selectedAuthMethod },
            set: { selectedAuthMethodRaw = $0.rawValue }
        )
    }

    private var autoSyncTaskID: String {
        "\(state.autoSyncEnabled)-\(Int(state.autoSyncIntervalSeconds))"
    }

    private var runtimeStatePublisher: AnyPublisher<AccountPoolState, Never> {
        runtimeModel?.$state.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()
    }

    private var runtimeSyncOutcomePublisher: AnyPublisher<AppPoolRuntimeModel.SyncOutcome, Never> {
        runtimeModel?.$lastSyncOutcome
            .compactMap { $0 }
            .eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()
    }

    private var appUpdateAutoCheckTaskID: String {
        "\(appUpdateAutoCheckEnabled)-\(appLanguageOverride)-\(isPrereleaseUpdateChannelEnabled)"
    }

    private var selectedLaunchTarget: CodexLaunchTarget {
        CodexLaunchTarget(
            rawValue: CodexLaunchTarget.normalizedRawValue(switchLaunchTargetRaw)
        ) ?? .auto
    }

    private static var defaultAccounts: [AgentAccount] {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: developerMockModeKey) else { return [] }
        return [
            AgentAccount(id: UUID(), name: "alpha@demo.local", usedUnits: 110, quota: PoolDashboardFormState.defaultQuota),
            AgentAccount(id: UUID(), name: "beta@demo.local", usedUnits: 420, quota: PoolDashboardFormState.defaultQuota),
            AgentAccount(id: UUID(), name: "gamma@demo.local", usedUnits: 730, quota: PoolDashboardFormState.defaultQuota),
            AgentAccount(id: UUID(), name: "delta@demo.local", usedUnits: 20, quota: PoolDashboardFormState.defaultQuota)
        ]
        #else
        []
        #endif
    }

    private var isDeveloperBuild: Bool {
        #if DEBUG || DEVELOPER_TOOLS_ENABLED
        true
        #else
        false
        #endif
    }

    private var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private enum Workspace: String, CaseIterable, Identifiable {
        case authentication
        case runtime
        case schedule
        case usageAnalytics
        case openAIResetAlert
        case settings
        case safety
        case developer

        var id: String { rawValue }

        var title: String {
            switch self {
            case .authentication: L10n.text("workspace.authentication.title")
            case .runtime: L10n.text("workspace.runtime.title")
            case .schedule: L10n.text("workspace.schedule.title")
            case .usageAnalytics: L10n.text("workspace.usage_analytics.title")
            case .openAIResetAlert: L10n.text("workspace.openai_reset_alert.title")
            case .settings: L10n.text("workspace.settings.title")
            case .safety: L10n.text("workspace.safety.title")
            case .developer: L10n.text("workspace.developer.title")
            }
        }

        var subtitle: String {
            switch self {
            case .authentication: L10n.text("workspace.authentication.subtitle")
            case .runtime: L10n.text("workspace.runtime.subtitle")
            case .schedule: L10n.text("workspace.schedule.subtitle")
            case .usageAnalytics: L10n.text("workspace.usage_analytics.subtitle")
            case .openAIResetAlert: L10n.text("workspace.openai_reset_alert.subtitle")
            case .settings: L10n.text("workspace.settings.subtitle")
            case .safety: L10n.text("workspace.safety.subtitle")
            case .developer: L10n.text("workspace.developer.subtitle")
            }
        }

        var symbolName: String {
            switch self {
            case .authentication: "person.badge.key"
            case .runtime: "dial.medium"
            case .schedule: "calendar.badge.clock"
            case .usageAnalytics: "chart.bar.xaxis"
            case .openAIResetAlert: "bell.badge.waveform"
            case .settings: "gearshape"
            case .safety: "shield.lefthalf.filled.badge.checkmark"
            case .developer: "wrench.and.screwdriver"
            }
        }
    }

    init(
        store: AccountPoolStoring = DeveloperAwareAccountPoolStore(),
        runtimeModel: AppPoolRuntimeModel? = nil
    ) {
        self.store = store
        self.runtimeModel = runtimeModel
        if let runtimeModel {
            _state = State(initialValue: runtimeModel.state)
        } else if let snapshot = store.load() {
            _state = State(initialValue: AccountPoolState(snapshot: snapshot))
        } else {
            var defaultState = Self.makeDefaultState(accounts: Self.defaultAccounts)
            defaultState.evaluate(now: .now)
            _state = State(initialValue: defaultState)
        }
    }

    private static func makeDefaultState(accounts: [AgentAccount]) -> AccountPoolState {
        AccountPoolState(
            accounts: accounts,
            mode: .intelligent,
            minSwitchInterval: 300,
            lowUsageThresholdRatio: 0.15
        )
    }

    var body: some View {
        ZStack {
            PoolDashboardTheme.backgroundGradient
                .ignoresSafeArea()
            Circle()
                .fill(PoolDashboardTheme.glowA.opacity(PoolDashboardTheme.glowAOpacity))
                .frame(width: PoolDashboardTheme.glowLargeSize, height: PoolDashboardTheme.glowLargeSize)
                .blur(radius: PoolDashboardTheme.glowLargeBlur)
                .offset(x: -300, y: -260)
                .allowsHitTesting(false)
            Circle()
                .fill(PoolDashboardTheme.glowB.opacity(PoolDashboardTheme.glowBOpacity))
                .frame(width: PoolDashboardTheme.glowMediumSize, height: PoolDashboardTheme.glowMediumSize)
                .blur(radius: PoolDashboardTheme.glowMediumBlur)
                .offset(x: 340, y: 220)
                .allowsHitTesting(false)
            Rectangle()
                .fill(
                    RadialGradient(
                        colors: [.clear, PoolDashboardTheme.vignetteEndColor],
                        center: .center,
                        startRadius: 120,
                        endRadius: 920
                    )
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

            dashboardContent
                .id(themeRenderToken)

            if let appUpdatePrompt {
                appUpdateOverlay(prompt: appUpdatePrompt)
                    .zIndex(10)
            } else if let whatsNewPrompt {
                whatsNewOverlay(announcement: whatsNewPrompt)
                    .zIndex(10)
            }
        }
        .frame(minWidth: PoolDashboardTheme.minWidth, minHeight: PoolDashboardTheme.minHeight)
        .onAppear {
            syncThemePaletteIfNeeded()
            refreshRelayAPIKeyReadiness()
            handleOnAppear()
            showWhatsNewIfNeeded()
        }
        .onChange(of: state.snapshot) { previousSnapshot, snapshot in
            let isRuntimeStateUpdate = isApplyingRuntimeStateUpdate
            isApplyingRuntimeStateUpdate = false
            if isRuntimeStateUpdate {
                suppressNextSnapshotDrivenSwitch = false
                return
            }
            let wasShowingLowUsageAlert = viewState.showLowUsageAlert
            showLowUsageAlertForThresholdTriggeredIntelligentSwitch(
                previousSnapshot: previousSnapshot,
                currentSnapshot: snapshot
            )
            handleSnapshotChange(snapshot, previousSnapshot: previousSnapshot)
            postLowUsageDesktopNotificationIfNeeded(
                wasShowingLowUsageAlert: wasShowingLowUsageAlert
            )
            guard !suppressNextSnapshotDrivenSwitch else {
                suppressNextSnapshotDrivenSwitch = false
                return
            }
            guard !viewState.isSyncingUsage else { return }
            Task { @MainActor in
                await triggerAutomaticSwitchActionIfNeeded(
                    previousMode: previousSnapshot.mode,
                    previousActiveAccountID: previousSnapshot.activeAccountID
                )
            }
        }
        .onReceive(runtimeStatePublisher) { nextState in
            guard runtimeModel != nil else { return }
            applyRuntimeStateUpdate(nextState)
        }
        .onReceive(runtimeSyncOutcomePublisher) { outcome in
            Task { @MainActor in
                await handleRuntimeSyncOutcome(outcome)
            }
        }
        .onChange(of: isDeveloperBuild) { _, isEnabled in
            if !isEnabled && selectedWorkspace == .developer {
                selectedWorkspace = .authentication
            }
        }
        .onChange(of: developerMockModeEnabled) { _, _ in
            guard isDebugBuild else { return }
            reloadStateForCurrentDataMode()
        }
        .onChange(of: specialResetWatchEnabled) { _, isEnabled in
            if isEnabled, specialResetWatchState.records.isEmpty {
                resetSpecialResetWatchBaseline()
            }
        }
        .onChange(of: state.groups) { _, groups in
            if groups.isEmpty {
                selectedGroupName = AgentAccount.defaultGroupName
            } else if !groups.contains(selectedGroupName) {
                selectedGroupName = groups[0]
            }
        }
        .onChange(of: selectedWorkspace) { _, _ in
            ensureUsageAnalyticsStateLoadedIfNeeded()
            releaseUsageAnalyticsStateIfPossible()
        }
        .onChange(of: appLanguageOverride) { _, value in
            let normalized = L10n.normalizedLanguageOverrideCode(value)
            if normalized != value {
                appLanguageOverride = normalized
            }
        }
        .onChange(of: appAppearanceOverride) { _, value in
            let normalized = AppAppearancePreference.normalizedRawValue(value)
            if normalized != value {
                appAppearanceOverride = normalized
            }
            syncThemePaletteIfNeeded()
        }
        .onChange(of: usageAnalyticsMaxStoredRecords) { _, value in
            let normalized = UsageAnalyticsEngine.clampedMaxStoredRecords(value)
            if normalized != value {
                usageAnalyticsMaxStoredRecords = normalized
                return
            }
            normalizeStoredUsageAnalyticsForCurrentLimit()
        }
        .onChange(of: colorScheme) { _, _ in
            syncThemePaletteIfNeeded()
        }
        .task(id: autoSyncTaskID) {
            await runDashboardAutoSyncTask()
        }
        .task(id: appUpdateAutoCheckTaskID) {
            await runAppUpdateAutoCheckTask()
        }
        .alert(L10n.text("alert.low_usage.title"), isPresented: $viewState.showLowUsageAlert) {
            Button(L10n.text("alert.dismiss"), role: .cancel) {
                viewState.lowUsageAlertMessage = nil
            }
        } message: {
            let message = viewState.lowUsageAlertMessage
                ?? alertPresenter.lowUsageAlertMessage(
                    activeAccount: state.activeAccount,
                    thresholdRatio: state.lowUsageAlertThresholdRatio
                )
            Text(message)
        }
        .preferredColorScheme(
            AppAppearancePreference.preferredColorScheme(
                for: AppAppearancePreference.normalizedRawValue(appAppearanceOverride)
            )
        )
    }

    private var dashboardContent: some View {
        HStack(alignment: .top, spacing: 0) {
            Group {
                if isSidebarCollapsed {
                    collapsedSidebarHandle
                } else {
                    workspaceSidebar
                }
            }

            Rectangle()
                .fill(PoolDashboardTheme.panelInnerStroke.opacity(0.85))
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            GeometryReader { contentGeometry in
                dashboardMainColumn(
                    viewportWidth: contentGeometry.size.width,
                    viewportHeight: contentGeometry.size.height
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PoolDashboardTheme.panelStrongFill.opacity(PoolDashboardTheme.chromeBaseOpacity))
        #if canImport(AppKit)
        .environment(\.controlActiveState, .active)
        #endif
        .groupBoxStyle(DashboardGroupBoxStyle())
        .animation(.easeInOut(duration: PoolDashboardTheme.standardAnimationDuration), value: state.mode)
        .animation(.easeInOut(duration: PoolDashboardTheme.fastAnimationDuration), value: viewState.showUsageRawJSON)
        .animation(.easeInOut(duration: PoolDashboardTheme.fastAnimationDuration), value: viewState.showSwitchLaunchLog)
        .animation(.easeInOut(duration: PoolDashboardTheme.fastAnimationDuration), value: selectedWorkspace)
    }

    private func dashboardMainColumn(
        viewportWidth: CGFloat,
        viewportHeight: CGFloat
    ) -> some View {
        let safeViewportWidth = max(0, viewportWidth)
        let contentWidth = Self.contentWidth(for: safeViewportWidth)

        return VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                dashboardScrollableContent(availableWidth: contentWidth)
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.horizontal, ResponsiveLayout.contentHorizontalPadding)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                    .frame(width: safeViewportWidth, alignment: .leading)
            }
            .frame(width: safeViewportWidth, alignment: .leading)

            workspaceCollapseToggle()
                .padding(.horizontal, ResponsiveLayout.contentHorizontalPadding)
                .padding(.bottom, 10)
                .background(
                    PoolDashboardTheme.panelStrongFill.opacity(PoolDashboardTheme.chromeFooterOpacity)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(PoolDashboardTheme.panelInnerStroke.opacity(0.75))
                                .frame(height: 1)
                        }
                )
                .frame(width: safeViewportWidth, alignment: .leading)

            if workspaceDrawerState.isVisible {
                workspaceDrawerPanel(
                    height: workspaceDrawerHeight(for: viewportHeight),
                    viewportWidth: safeViewportWidth
                )
            }
        }
        .frame(width: safeViewportWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func dashboardScrollableContent(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: PoolDashboardTheme.sectionSpacing) {
            dashboardHeaderChrome(availableWidth: availableWidth)
            accountUsagePanel(availableWidth: availableWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func dashboardHeaderChrome(availableWidth: CGFloat) -> some View {
        if Self.usesStackedDashboardChrome(availableWidth: availableWidth) {
            VStack(alignment: .leading, spacing: 10) {
                dashboardHeaderSection
                syncToolbarPanel
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                dashboardHeaderSection
                syncToolbarPanel
            }
        }
    }

    private var dashboardHeaderSection: some View {
        DashboardHeaderSectionView(
            accountCount: state.uniqueAccountsCount,
            availableCount: state.availableAccountsCount,
            overallUsagePercent: Int(state.overallUsageRatio * 100),
            modeTitle: state.mode.rawValue
        )
    }

    private static func contentWidth(for viewportWidth: CGFloat) -> CGFloat {
        max(0, viewportWidth - ResponsiveLayout.contentHorizontalPadding * 2)
    }

    private static func usesStackedDashboardChrome(availableWidth: CGFloat) -> Bool {
        availableWidth < ResponsiveLayout.dashboardChromeStackBreakpoint
    }

    private static func usesStackedWorkspaceContent(availableWidth: CGFloat) -> Bool {
        availableWidth < ResponsiveLayout.workspaceContentStackBreakpoint
    }

    private var collapsedSidebarHandle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: PoolDashboardTheme.fastAnimationDuration)) {
                    isSidebarCollapsed = false
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PoolDashboardTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(PoolDashboardTheme.panelMutedFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .frame(width: 40, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 14)
        .background(PoolDashboardTheme.panelMutedFill.opacity(PoolDashboardTheme.chromeSidebarOpacity))
    }

    private func workspaceDrawerHeight(for availableHeight: CGFloat) -> CGFloat {
        switch workspaceDrawerState {
        case .collapsed:
            return 0
        case .partial:
            return min(440, max(300, availableHeight * 0.38))
        case .expanded:
            return max(260, availableHeight - 56)
        }
    }

    private func workspaceDrawerPanel(height: CGFloat, viewportWidth: CGFloat) -> some View {
        let safeViewportWidth = max(0, viewportWidth)
        let contentWidth = Self.contentWidth(for: safeViewportWidth)

        return VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(PoolDashboardTheme.panelInnerStroke.opacity(0.75))
                .frame(height: 1)

            ScrollView(showsIndicators: false) {
                workspaceContent(availableWidth: contentWidth)
                    .id(selectedWorkspace.id)
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.horizontal, ResponsiveLayout.contentHorizontalPadding)
                    .padding(.vertical, 12)
                    .frame(width: safeViewportWidth, alignment: .leading)
            }
            .frame(width: safeViewportWidth, height: height, alignment: .topLeading)
            .background(PoolDashboardTheme.panelStrongFill.opacity(PoolDashboardTheme.chromeStrongOpacity))
        }
        .frame(width: safeViewportWidth, alignment: .topLeading)
    }

    private func workspaceCollapseToggle() -> some View {
        HStack(spacing: 8) {
            Image(systemName: workspaceDrawerState.symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(PoolDashboardTheme.textMuted)
                .frame(width: 12)

            Text(selectedWorkspace.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(PoolDashboardTheme.textSecondary)

            Rectangle()
                .fill(PoolDashboardTheme.panelInnerStroke.opacity(0.9))
                .frame(height: 1)

            Text(L10n.text(workspaceDrawerState.actionTitleKey))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PoolDashboardTheme.textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PoolDashboardTheme.panelMutedFill.opacity(PoolDashboardTheme.isLightPalette ? 0.72 : 0.45))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: PoolDashboardTheme.fastAnimationDuration)) {
                workspaceDrawerState = workspaceDrawerState.next()
            }
        }
    }

    private var workspaceSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L10n.text("workspace.list_title").uppercased())
                    .font(PoolDashboardTheme.metadataFont.weight(.semibold))
                    .tracking(PoolDashboardTheme.metadataTracking)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeInOut(duration: PoolDashboardTheme.fastAnimationDuration)) {
                        isSidebarCollapsed = true
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(PoolDashboardTheme.panelMutedFill)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)

            ForEach(visibleWorkspaces) { workspace in
                workspaceButton(for: workspace)
            }

            Spacer(minLength: 0)

            if let appUpdateAvailablePrompt {
                sidebarUpdateButton(prompt: appUpdateAvailablePrompt)
            }
        }
        .frame(width: PoolDashboardTheme.workspaceSidebarWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.vertical, PoolDashboardTheme.workspaceSidebarPadding)
        .padding(.horizontal, 10)
        .background(PoolDashboardTheme.panelMutedFill.opacity(PoolDashboardTheme.chromeSidebarOpacity))
    }

    private var visibleWorkspaces: [Workspace] {
        var workspaces = Workspace.allCases.filter { workspace in
            if workspace == .developer {
                return isDeveloperBuild
            }
            return true
        }
        if let resetAlertIndex = workspaces.firstIndex(of: .openAIResetAlert) {
            let resetAlertWorkspace = workspaces.remove(at: resetAlertIndex)
            workspaces.append(resetAlertWorkspace)
        }
        return workspaces
    }

    private func workspaceContent(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: PoolDashboardTheme.sectionSpacing) {
            PanelSectionHeaderView(
                title: selectedWorkspace.title,
                subtitle: selectedWorkspace.subtitle,
                symbolName: selectedWorkspace.symbolName
            )

            if hasWorkspaceContextPanel {
                if Self.usesStackedWorkspaceContent(availableWidth: availableWidth) {
                    VStack(alignment: .leading, spacing: PoolDashboardTheme.sectionSpacing) {
                        workspaceMainPanel
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        workspaceContextPanel
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                } else {
                    HStack(alignment: .top, spacing: PoolDashboardTheme.sectionSpacing) {
                        workspaceMainPanel
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        workspaceContextPanel
                            .frame(width: PoolDashboardTheme.workspaceContextWidth, alignment: .topLeading)
                    }
                }
            } else {
                workspaceMainPanel
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hasWorkspaceContextPanel: Bool {
        switch selectedWorkspace {
        case .authentication:
            return selectedAuthMethod == .oauth
        case .runtime, .schedule, .usageAnalytics, .openAIResetAlert, .settings, .safety:
            return false
        default:
            return true
        }
    }

    @ViewBuilder
    private var workspaceMainPanel: some View {
        switch selectedWorkspace {
        case .authentication:
            authenticationRoutePanel
        case .runtime:
            strategySettingsPanel
        case .schedule:
            schedulePanel
        case .usageAnalytics:
            usageAnalyticsPanel
        case .openAIResetAlert:
            specialResetWatchPanel
        case .settings:
            workspaceSettingsPanel
        case .safety:
            backupRestorePanel
        case .developer:
            debugToolsPanel
        }
    }

    @ViewBuilder
    private var workspaceContextPanel: some View {
        switch selectedWorkspace {
        case .authentication:
            localOAuthAccountsPanel
        case .runtime:
            activeAccountPanel
        case .schedule:
            EmptyView()
        case .usageAnalytics:
            EmptyView()
        case .openAIResetAlert:
            EmptyView()
        case .settings:
            EmptyView()
        case .safety:
            EmptyView()
        case .developer:
            developerContextPanel
        }
    }

    private var developerContextPanel: some View {
        GroupBox(L10n.text("developer.diagnostics.title")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("developer.diagnostics.subtitle"))
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                if isDebugBuild {
                    GroupBox(L10n.text("developer.data_mode.title")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(L10n.text("developer.data_mode.toggle"), isOn: $developerMockModeEnabled)
                                .toggleStyle(.switch)

                            Text(
                                developerMockModeEnabled
                                ? L10n.text("developer.data_mode.enabled_hint")
                                : L10n.text("developer.data_mode.disabled_hint")
                            )
                            .font(.caption)
                            .foregroundStyle(PoolDashboardTheme.textMuted)

                            HStack(spacing: 8) {
                                Button(L10n.text("developer.data_mode.seed")) {
                                    seedDeveloperMockData()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(PoolDashboardTheme.glowA)
                                .disabled(!developerMockModeEnabled)

                                Button(L10n.text("developer.data_mode.clear")) {
                                    clearCurrentDataModeStore()
                                }
                                .buttonStyle(DashboardWarningButtonStyle())
                            }
                        }
                    }
                    .sectionCardStyle()
                }

                Button(L10n.text("developer.notification.test_button")) {
                    DesktopNotifier.post(
                        key: "manual-test-notification",
                        title: L10n.text("developer.notification.test_title"),
                        body: notificationUsageSummary(for: state.activeAccount),
                        minInterval: 0
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(PoolDashboardTheme.glowA)

                activityLogPanel
            }
        }
        .sectionCardStyle()
    }

    private func workspaceButton(for workspace: Workspace) -> some View {
        let isSelected = selectedWorkspace == workspace
        let isResetAlert = workspace == .openAIResetAlert

        return Button {
            selectedWorkspace = workspace
            if workspaceDrawerState == .collapsed {
                withAnimation(.easeInOut(duration: PoolDashboardTheme.fastAnimationDuration)) {
                    workspaceDrawerState = .partial
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: workspace.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text(workspace.subtitle)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                }

                Spacer(minLength: 0)

                if isResetAlert {
                    Text(L10n.text("special_reset.badge"))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.48, blue: 0.24), Color(red: 0.95, green: 0.22, blue: 0.16)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: PoolDashboardTheme.workspaceSidebarItemCornerRadius, style: .continuous)
                    .fill(
                        isResetAlert
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.56, blue: 0.28).opacity(isSelected ? 0.30 : 0.15),
                                    Color(red: 0.94, green: 0.24, blue: 0.18).opacity(isSelected ? 0.24 : 0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        : AnyShapeStyle(isSelected ? PoolDashboardTheme.panelStrongFill : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.workspaceSidebarItemCornerRadius, style: .continuous)
                            .stroke(
                                isResetAlert
                                ? Color(red: 1.0, green: 0.56, blue: 0.28).opacity(isSelected ? 0.95 : 0.55)
                                : (isSelected ? PoolDashboardTheme.glowA.opacity(0.5) : PoolDashboardTheme.panelInnerStroke),
                                lineWidth: 1
                            )
                    )
            )
            .contentShape(
                RoundedRectangle(cornerRadius: PoolDashboardTheme.workspaceSidebarItemCornerRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            isResetAlert
            ? (isSelected ? PoolDashboardTheme.textPrimary : Color(red: 1.0, green: 0.72, blue: 0.56))
            : (isSelected ? PoolDashboardTheme.textPrimary : PoolDashboardTheme.textSecondary)
        )
    }

    private func sidebarUpdateButton(prompt: AppUpdatePrompt) -> some View {
        Button {
            appUpdatePrompt = prompt
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 13, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("update.prompt.install_now"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text(prompt.latestVersion)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
        .buttonStyle(DashboardWarningButtonStyle())
    }

    private var syncToolbarPanel: some View {
        SyncToolbarView(
            isSyncing: viewState.isSyncingUsage,
            lastSyncAt: state.lastUsageSyncAt,
            errorText: viewState.syncError
        ) {
            Task { await syncCodexUsage() }
        } onRetry: {
            Task { await retrySyncCodexUsage() }
        } onForceRetry: {
            Task { await forceRetrySyncCodexUsage() }
        }
    }

    private var authenticationRoutePanel: some View {
        VStack(alignment: .leading, spacing: PoolDashboardTheme.sectionSpacing) {
            authMethodSelector
            selectedAuthMethodPanel
        }
    }

    private var authMethodSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: selectedAuthMethod.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                Text(L10n.text("auth.method.title"))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PoolDashboardTheme.textPrimary)
            }

            Picker(L10n.text("auth.method.title"), selection: authMethodBinding) {
                ForEach(AuthMethod.allCases) { method in
                    Text(method.title).tag(method)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("auth.method.picker")

            Text(selectedAuthMethod.subtitle)
                .font(.footnote)
                .foregroundStyle(PoolDashboardTheme.textMuted)
                .frame(maxWidth: PoolDashboardTheme.subtitleReadableWidth, alignment: .leading)
        }
        .dashboardInfoCard()
    }

    @ViewBuilder
    private var selectedAuthMethodPanel: some View {
        switch selectedAuthMethod {
        case .oauth:
            oauthLoginPanel
        case .relayAPIKey:
            relayAPIKeyPanel
        }
    }

    private var oauthLoginPanel: some View {
        OAuthLoginPanelView(
            oauthIssuer: $oauthIssuer,
            oauthClientID: $oauthClientID,
            oauthScopes: $oauthScopes,
            oauthRedirectURI: $oauthRedirectURI,
            oauthOriginator: $oauthOriginator,
            oauthWorkspaceID: $oauthWorkspaceID,
            oauthAccountName: $formState.oauthAccountName,
            oauthAccountQuota: $formState.oauthAccountQuota,
            manualCallbackURL: $manualOAuthCallbackURL,
            isSigningInOAuth: viewState.isSigningInOAuth,
            oauthSuccessMessage: viewState.oauthSuccessMessage,
            oauthError: viewState.oauthError,
            manualAuthorizationURLOverride: pendingManualOAuthContext?.authorizationURL.absoluteString,
            showManualImportSection: pendingManualOAuthContext != nil,
            onSignIn: {
                startOAuthTask {
                    await signInWithOAuth()
                }
            },
            onCopyURLAndManualSignIn: {
                prepareManualOAuthSignIn()
            },
            onManualImport: {
                startOAuthTask {
                    await importManualOAuthCallback()
                }
            },
            onCancelSignIn: {
                cancelOAuthSignIn()
            }
        )
    }

    private var relayAPIKeyPanel: some View {
        RelayAPIKeyPanelView(
            accountName: $formState.relayAccountName,
            providerID: relayProviderIDBinding,
            providerName: $formState.relayProviderName,
            baseURL: relayBaseURLBinding,
            wireAPI: $formState.relayWireAPI,
            apiKey: relayAPIKeyBinding,
            preserveOfficialAuth: $relayPreserveOfficialAuth,
            canAddRelayAccount: canAddRelayAccount,
            successMessage: viewState.relaySuccessMessage,
            errorMessage: viewState.relayError,
            onAddRelayAccount: {
                addRelayAccount()
            }
        )
    }

    private var relayProviderIDBinding: Binding<String> {
        Binding(
            get: { formState.relayProviderID },
            set: {
                formState.relayProviderID = $0
                refreshRelayAPIKeyReadiness()
            }
        )
    }

    private var relayBaseURLBinding: Binding<String> {
        Binding(
            get: { formState.relayBaseURL },
            set: {
                formState.relayBaseURL = $0
                refreshRelayAPIKeyReadiness()
            }
        )
    }

    private var relayAPIKeyBinding: Binding<String> {
        Binding(
            get: { formState.relayAPIKey },
            set: {
                formState.relayAPIKey = $0
                refreshRelayAPIKeyReadiness()
            }
        )
    }

    private func refreshRelayAPIKeyReadiness() {
        canAddRelayAccount = RelayAPIKeyFormReadiness.canAdd(
            providerID: formState.relayProviderID,
            baseURL: formState.relayBaseURL,
            apiKey: formState.relayAPIKey
        )
    }

    private var localOAuthAccountsPanel: some View {
        LocalOAuthAccountsPanelView(
            accounts: localOAuthImportViewModel.accounts,
            errorMessage: localOAuthImportViewModel.errorMessage,
            successMessage: localOAuthImportViewModel.successMessage,
            importingAccountID: importingLocalOAuthAccountID,
            onScan: {
                refreshLocalOAuthAccounts()
            },
            onChooseAuthFile: {
                _ = openAuthFilePanel()
            },
            onImport: { account in
                await importLocalOAuthAccount(account)
            }
        )
    }

    private var strategySettingsPanel: some View {
        StrategySettingsPanelView(
            mode: state.mode == .manual ? .intelligent : state.mode,
            accounts: state.accounts,
            activeAccount: state.activeAccount,
            intelligentCandidateName: intelligentCandidateName,
            canIntelligentSwitch: state.canIntelligentSwitch(),
            intelligentCooldownRemaining: state.intelligentSwitchCooldownRemaining(),
            hasLowUsageWarning: state.hasLowUsageWarning,
            modeBinding: strategyBindings.mode,
            manualSelectionBinding: strategyBindings.manualSelection,
            minSwitchIntervalBinding: strategyBindings.minSwitchInterval,
            switchThresholdBinding: strategyBindings.lowThreshold,
            lowUsageAlertThresholdBinding: strategyBindings.lowUsageAlertThreshold,
            lowUsageAlertsEnabledBinding: strategyBindings.lowUsageAlertsEnabled
        )
    }

    private var workspaceSettingsPanel: some View {
        WorkspaceSettingsPanelView(
            switchWithoutLaunchingBinding: strategyBindings.switchWithoutLaunching,
            launchTargetBinding: $switchLaunchTargetRaw,
            autoSyncEnabledBinding: strategyBindings.autoSyncEnabled,
            autoSyncIntervalSecondsBinding: strategyBindings.autoSyncIntervalSeconds,
            languageOverrideBinding: $appLanguageOverride,
            appearanceOverrideBinding: $appAppearanceOverride,
            usageAnalyticsMaxStoredRecordsBinding: $usageAnalyticsMaxStoredRecords,
            languageOptions: L10n.languageOptions,
            appUpdateAutoCheckEnabledBinding: $appUpdateAutoCheckEnabled,
            isCheckingForUpdates: isCheckingForAppUpdate,
            appUpdateStatusMessage: appUpdateStatusMessage,
            onCheckForUpdates: {
                if sparkleUpdateDriver.startUserInitiatedUpdate() {
                    appUpdateStatusMessage = L10n.text("update.status.sparkle_started")
                } else if sparkleUpdateDriver.isAvailable {
                    appUpdateStatusMessage = L10n.text("update.status.direct_unavailable")
                } else {
                    Task { await checkForAppUpdates(force: true) }
                }
            },
            onShowWhatsNew: {
                showWhatsNewManually()
            }
        )
    }

    private var schedulePanel: some View {
        DailyUsagePlanningWorkspacePanelView(
            accounts: state.accounts,
            analyticsState: usageAnalyticsState
        )
        .onAppear {
            ensureUsageAnalyticsStateLoaded()
        }
    }

    private var usageAnalyticsPanel: some View {
        UsageAnalyticsWorkspacePanelView(
            analyticsState: usageAnalyticsState,
            accounts: state.accounts,
            onClearIdleDelay: clearUsageAnalyticsIdleDelay
        )
        .onAppear {
            ensureUsageAnalyticsStateLoaded()
        }
    }

    private var specialResetWatchPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text(L10n.text("special_reset.title"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(PoolDashboardTheme.textPrimary.opacity(PoolDashboardTheme.groupLabelOpacity))

                    Spacer(minLength: 0)

                    Button(L10n.text("special_reset.reset_baseline")) {
                        resetSpecialResetWatchBaseline()
                    }
                    .buttonStyle(.bordered)

                    Button(L10n.text("special_reset.clear_events")) {
                        clearSpecialResetWatchEvents()
                    }
                    .buttonStyle(.bordered)
                }

                Text(L10n.text("special_reset.subtitle"))
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                HStack(spacing: 12) {
                    Toggle(L10n.text("special_reset.enable_monitor"), isOn: $specialResetWatchEnabled)
                        .toggleStyle(.switch)
                    Toggle(L10n.text("special_reset.enable_notification"), isOn: $specialResetWatchNotifyEnabled)
                        .toggleStyle(.switch)
                        .disabled(!specialResetWatchEnabled)
                }

                Stepper(value: $specialResetWatchGraceMinutes, in: 0...240, step: 1) {
                    Text(L10n.text("special_reset.grace_minutes_format", specialResetWatchGraceMinutes))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                }
                .disabled(!specialResetWatchEnabled)

                HStack(spacing: 8) {
                    specialResetSummaryCard(
                        title: L10n.text("special_reset.summary.paid_accounts"),
                        value: "\(uniquePaidAccountCount())"
                    )
                    specialResetSummaryCard(
                        title: L10n.text("special_reset.summary.last_checked"),
                        value: specialResetWatchState.lastEvaluatedAt.map(specialResetDateText) ?? L10n.text("schedule.summary.not_available")
                    )
                    specialResetSummaryCard(
                        title: L10n.text("special_reset.summary.detected"),
                        value: "\(specialResetWatchState.events.count)"
                    )
                }

                if let latest = specialResetWatchState.events.first {
                    PanelStatusCalloutView(
                        message: specialResetEventMessage(for: latest),
                        title: L10n.text("special_reset.detected_title"),
                        tone: .warning
                    )
                } else {
                    PanelStatusCalloutView(
                        message: L10n.text("special_reset.empty"),
                        title: L10n.text("special_reset.detected_title"),
                        tone: .success
                    )
                }

                if !specialResetWatchState.records.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("special_reset.records_title"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PoolDashboardTheme.textPrimary)

                        ForEach(Array(specialResetWatchState.records.prefix(8))) { record in
                            let displayedDates = specialResetDisplayedResetDates(for: record)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.accountName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(PoolDashboardTheme.textPrimary)
                                Text(
                                    L10n.text(
                                        "special_reset.records_row_format",
                                        displayedDates.weekly,
                                        displayedDates.fiveHour
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(PoolDashboardTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                    }
                    .dashboardInfoCard()
                }
            }
        }
        .sectionCardStyle()
    }

    private func specialResetSummaryCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PoolDashboardTheme.textMuted)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PoolDashboardTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardInfoCard()
    }

    private var activeAccountPanel: some View {
        ActiveAccountPanelView(
            activeAccount: state.activeAccount,
            mode: state.mode,
            isFocusLockActive: state.isFocusLockActive,
            hasLowUsageWarning: state.hasLowUsageWarning,
            lowUsageAlertThresholdRatio: state.lowUsageAlertThresholdRatio,
            showSimulationControl: isDeveloperBuild,
            onSimulateUsage: {
                handleSimulateUsage()
            },
            onEvaluateSwitch: {
                handleEvaluateSwitch()
            }
        )
    }

    private func accountUsagePanel(availableWidth: CGFloat) -> some View {
        AccountUsagePanelView(
            newAccountName: $formState.newAccountName,
            newAccountQuota: $formState.newAccountQuota,
            selectedGroupName: $selectedGroupName,
            availableWidth: availableWidth,
            accounts: state.accounts,
            groups: state.groups,
            activeAccountID: state.activeAccountID,
            switchLaunchError: viewState.switchLaunchError,
            switchLaunchWarning: viewState.switchLaunchWarning,
            showAddAccountControls: isDeveloperBuild,
            onAddAccount: { name, quota in
                handleAddAccount(name: name, quota: quota)
            },
            onSwitchAndLaunch: { accountID in
                await switchAndLaunchCodex(using: accountID)
            },
            onRemoveAccount: { accountID in
                handleRemoveAccount(accountID: accountID)
            },
            onMoveAccountToGroup: { accountID, group in
                handleMoveAccount(accountID: accountID, to: group)
            },
            onCreateGroup: { name in
                handleCreateGroup(name: name)
            },
            onRenameGroup: { oldName, newName in
                handleRenameGroup(from: oldName, to: newName)
            },
            onDeleteGroup: { name in
                handleDeleteGroup(name: name)
            },
            accountNameBinding: { accountID in
                accountBindings.nameBinding(for: accountID)
            },
            accountQuotaBinding: { accountID in
                accountBindings.quotaBinding(for: accountID)
            },
            accountUsedBinding: { accountID in
                accountBindings.usedBinding(for: accountID)
            },
            isPercentUsageAccount: { account in
                usagePresenter.isPercentUsageAccount(account)
            },
            remainingLabel: { account in
                usagePresenter.remainingLabel(for: account)
            },
            usageProgressColor: { account in
                usagePresenter.usageProgressColor(for: account)
            }
        )
    }

    private var activityLogPanel: some View {
        ActivityLogPanelView(
            activities: state.activities,
            onClearActivities: {
                handleClearActivities()
            }
        )
    }

    private func uniquePaidAccountCount() -> Int {
        Set(state.accounts.filter(\.isPaid).map(\.deduplicationKey)).count
    }

    private var backupRestorePanel: some View {
        BackupRestorePanelView(
            backupJSON: $viewState.backupJSON,
            backupError: $viewState.backupError,
            onExport: exportSnapshot,
            onExportRefetchable: exportRefetchableSnapshot,
            onImport: importSnapshot
        )
    }

    private var debugToolsPanel: some View {
        DebugToolsPanelView(
            showUsageRawJSON: $viewState.showUsageRawJSON,
            lastUsageRawJSON: $viewState.lastUsageRawJSON,
            showSwitchLaunchLog: $viewState.showSwitchLaunchLog,
            lastSwitchLaunchLog: $viewState.lastSwitchLaunchLog,
            diagnostics: debugDiagnostics
        )
    }

    private var debugDiagnostics: [DebugDiagnosticMetric] {
        let tokenStorage = activeTokenStorage()
        let accountIDs = Set(state.accounts.map { $0.id.uuidString })
        let orphanTokenCount = tokenStorage.keys.filter { !accountIDs.contains($0) }.count

        return [
            DebugDiagnosticMetric(
                id: "accounts",
                title: L10n.text("debug_tools.metric.accounts"),
                value: "\(state.accounts.count)"
            ),
            DebugDiagnosticMetric(
                id: "tokens",
                title: L10n.text("debug_tools.metric.tokens"),
                value: "\(tokenStorage.count)"
            ),
            DebugDiagnosticMetric(
                id: "orphan_tokens",
                title: L10n.text("debug_tools.metric.orphan_tokens"),
                value: "\(orphanTokenCount)"
            ),
            DebugDiagnosticMetric(
                id: "activities",
                title: L10n.text("debug_tools.metric.activities"),
                value: "\(state.activities.count)"
            ),
            DebugDiagnosticMetric(
                id: "analytics_records",
                title: L10n.text("debug_tools.metric.analytics_records"),
                value: usageAnalyticsStateLoaded ? "\(usageAnalyticsState.records.count)" : L10n.text("debug_tools.metric.lazy")
            ),
            DebugDiagnosticMetric(
                id: "analytics_snapshots",
                title: L10n.text("debug_tools.metric.analytics_snapshots"),
                value: usageAnalyticsStateLoaded ? "\(usageAnalyticsState.snapshots.count)" : L10n.text("debug_tools.metric.lazy")
            ),
            DebugDiagnosticMetric(
                id: "reset_watch",
                title: L10n.text("debug_tools.metric.reset_watch"),
                value: "\(specialResetWatchState.records.count)/\(specialResetWatchState.events.count)"
            ),
            DebugDiagnosticMetric(
                id: "local_oauth",
                title: L10n.text("debug_tools.metric.local_oauth"),
                value: "\(localOAuthImportViewModel.accounts.count)"
            ),
            DebugDiagnosticMetric(
                id: "raw_json",
                title: L10n.text("debug_tools.metric.raw_json"),
                value: byteCountText(viewState.lastUsageRawJSON)
            ),
            DebugDiagnosticMetric(
                id: "backup_json",
                title: L10n.text("debug_tools.metric.backup_json"),
                value: byteCountText(viewState.backupJSON)
            )
        ]
    }

    private func activeTokenStorage() -> [String: String] {
        let key = isDebugBuild && developerMockModeEnabled ? Self.developerTokenKey : Self.productionTokenKey
        return UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private func byteCountText(_ value: String) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value.utf8.count), countStyle: .memory)
    }

    @ViewBuilder
    private func pairedPanels<Primary: View, Secondary: View>(
        primary: Primary,
        secondary: Secondary
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: PoolDashboardTheme.sectionSpacing) {
                primary.frame(maxWidth: .infinity, alignment: .topLeading)
                secondary.frame(maxWidth: .infinity, alignment: .topLeading)
            }
            VStack(alignment: .leading, spacing: PoolDashboardTheme.sectionSpacing) {
                primary
                secondary
            }
        }
    }

    // MARK: - Lifecycle

    private func handleOnAppear() {
        migrateDefaultOAuthClientIDIfNeeded()
        migrateLanguagePreferenceIfNeeded()
        migrateAppearancePreferenceIfNeeded()
        migrateSpecialResetGraceMinutesIfNeeded()
        loadSpecialResetWatchStateFromStorage()
        ensureUsageAnalyticsStateLoadedIfNeeded()
        DesktopNotifier.requestAuthorizationIfNeeded()

        let output = lifecycleFlowCoordinator.onAppear(
            state: state,
            lowUsageAlertPolicy: lowUsageAlertPolicy,
            viewModel: localOAuthImportViewModel,
            authFileAccessService: authFileAccessService,
            currentAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL
        )
        applyLifecycleOnAppearOutput(output)
        store.save(state.snapshot)
        evaluateSpecialResetWatchAfterSync(now: .now)
        seedUsageAnalyticsIfNeeded(now: .now)
        WidgetBridgePublisher.publish(from: state.snapshot)
    }

    // MARK: - Developer Data Mode

    private func reloadStateForCurrentDataMode() {
        let output = Self.dataModeReloadOutput(
            snapshot: store.load(),
            selectedGroupName: selectedGroupName,
            defaultAccounts: Self.defaultAccounts,
            now: .now
        )
        state = output.state
        selectedGroupName = output.selectedGroupName

        lowUsageAlertPolicy = LowUsageAlertPolicy()
        viewState.showLowUsageAlert = false
        viewState.lowUsageAlertMessage = nil
        usageAnalyticsState = UsageAnalyticsState()
        usageAnalyticsStateLoaded = false
        seedUsageAnalyticsIfNeeded(now: .now)
        WidgetBridgePublisher.publish(from: state.snapshot)
    }

    private static func dataModeReloadOutput(
        snapshot: AccountPoolSnapshot?,
        selectedGroupName: String,
        defaultAccounts: [AgentAccount],
        now: Date
    ) -> DataModeReloadOutput {
        let nextState: AccountPoolState
        if let snapshot {
            nextState = AccountPoolState(snapshot: snapshot)
        } else {
            var defaultState = makeDefaultState(accounts: defaultAccounts)
            defaultState.evaluate(now: now)
            nextState = defaultState
        }

        let nextSelectedGroupName: String
        if nextState.groups.isEmpty {
            nextSelectedGroupName = AgentAccount.defaultGroupName
        } else if nextState.groups.contains(selectedGroupName) {
            nextSelectedGroupName = selectedGroupName
        } else {
            nextSelectedGroupName = nextState.groups[0]
        }

        return DataModeReloadOutput(
            state: nextState,
            selectedGroupName: nextSelectedGroupName
        )
    }

    private func seedDeveloperMockData() {
        guard isDebugBuild, developerMockModeEnabled else { return }

        var seededState = Self.makeDefaultState(accounts: Self.defaultAccounts)
        seededState.evaluate(now: .now)
        state = seededState
        store.save(seededState.snapshot)
        WidgetBridgePublisher.publish(from: seededState.snapshot)
    }

    private func clearCurrentDataModeStore() {
        let defaults = UserDefaults.standard
        if isDebugBuild && developerMockModeEnabled {
            defaults.removeObject(forKey: Self.developerSnapshotKey)
            defaults.removeObject(forKey: Self.developerTokenKey)
        } else {
            defaults.removeObject(forKey: Self.productionSnapshotKey)
            defaults.removeObject(forKey: Self.productionTokenKey)
        }
        reloadStateForCurrentDataMode()
    }

    private func migrateDefaultOAuthClientIDIfNeeded() {
        guard oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        oauthClientID = Self.defaultOAuthClientID
    }

    private func migrateAppearancePreferenceIfNeeded() {
        appAppearanceOverride = AppAppearancePreference.normalizedRawValue(appAppearanceOverride)
    }

    private func migrateLanguagePreferenceIfNeeded() {
        appLanguageOverride = L10n.normalizedLanguageOverrideCode(appLanguageOverride)
    }

    private func migrateSpecialResetGraceMinutesIfNeeded() {
        guard !didMigrateSpecialResetGraceMinutes else { return }
        // Previous default was 30. Migrate untouched installs to the new 1-minute default.
        if specialResetWatchGraceMinutes == 30 {
            specialResetWatchGraceMinutes = 1
        }
        didMigrateSpecialResetGraceMinutes = true
    }

    private func syncThemePaletteIfNeeded() {
        let isLight = resolvedLightPalette()
        if PoolDashboardTheme.forcePalette(isLight: isLight) {
            themeRenderToken &+= 1
        }
    }

    private func resolvedLightPalette() -> Bool {
        let normalizedAppearance = AppAppearancePreference.normalizedRawValue(appAppearanceOverride)
        switch AppAppearancePreference(rawValue: normalizedAppearance) ?? .system {
        case .light:
            return true
        case .dark:
            return false
        case .system:
            return colorScheme == .light
        }
    }

    private func handleSnapshotChange(
        _ snapshot: AccountPoolSnapshot,
        previousSnapshot: AccountPoolSnapshot,
        currentState: AccountPoolState? = nil
    ) {
        let currentState = currentState ?? state
        if runtimeModel == nil {
            WidgetBridgePublisher.publish(from: snapshot)
        }
        let output = lifecycleFlowCoordinator.onSnapshotChanged(
            snapshot: snapshot,
            state: currentState,
            lowUsageAlertPolicy: lowUsageAlertPolicy,
            viewState: viewState,
            store: runtimeModel == nil ? store : RuntimeOwnedSnapshotStore()
        )
        applyLifecycleSnapshotChangeOutput(output)
        if let runtimeModel, runtimeModel.state.snapshot != currentState.snapshot {
            runtimeModel.replaceStateFromDashboard(currentState)
            if autoSyncCadenceChanged(from: previousSnapshot, to: snapshot) {
                runtimeModel.restartAutoSyncIfNeeded()
            }
        }
    }

    private func applyRuntimeStateUpdate(_ nextState: AccountPoolState) {
        guard state.snapshot != nextState.snapshot else { return }
        isApplyingRuntimeStateUpdate = true
        suppressNextSnapshotDrivenSwitch = true
        state = nextState
    }

    private func autoSyncCadenceChanged(
        from previousSnapshot: AccountPoolSnapshot,
        to snapshot: AccountPoolSnapshot
    ) -> Bool {
        previousSnapshot.autoSyncEnabled != snapshot.autoSyncEnabled
            || previousSnapshot.autoSyncIntervalSeconds != snapshot.autoSyncIntervalSeconds
    }

    private func showLowUsageAlertForThresholdTriggeredIntelligentSwitch(
        previousSnapshot: AccountPoolSnapshot,
        currentSnapshot: AccountPoolSnapshot
    ) {
        guard let message = lowUsageAlertMessageForThresholdTriggeredIntelligentSwitch(
            previousSnapshot: previousSnapshot,
            currentSnapshot: currentSnapshot
        ) else {
            return
        }

        viewState.lowUsageAlertMessage = message
        viewState.showLowUsageAlert = true
    }

    private func lowUsageAlertMessageForThresholdTriggeredIntelligentSwitch(
        previousSnapshot: AccountPoolSnapshot,
        currentSnapshot: AccountPoolSnapshot
    ) -> String? {
        guard previousSnapshot.lowUsageAlertsEnabled else { return nil }
        guard previousSnapshot.mode == .intelligent, currentSnapshot.mode == .intelligent else { return nil }
        guard previousSnapshot.activeAccountID != currentSnapshot.activeAccountID else { return nil }
        guard let previousAccountID = previousSnapshot.activeAccountID,
              let previousAccount = previousSnapshot.accounts.first(where: { $0.id == previousAccountID })
        else {
            return nil
        }

        let thresholdRatio = previousSnapshot.lowUsageThresholdRatio
        guard intelligentRemainingRatio(for: previousAccount) <= thresholdRatio else { return nil }

        return alertPresenter.lowUsageAlertMessage(
            activeAccount: previousAccount,
            thresholdRatio: thresholdRatio
        )
    }

    private func postLowUsageDesktopNotificationIfNeeded(
        wasShowingLowUsageAlert: Bool
    ) {
        guard let request = lowUsageDesktopNotificationRequestIfNeeded(
            wasShowingLowUsageAlert: wasShowingLowUsageAlert
        ) else { return }

        DesktopNotifier.post(
            key: request.key,
            title: request.title,
            body: request.body,
            minInterval: request.minInterval
        )
    }

    private func lowUsageDesktopNotificationRequestIfNeeded(
        wasShowingLowUsageAlert: Bool
    ) -> DashboardNotificationRequest? {
        Self.lowUsageDesktopNotificationRequestIfNeeded(
            state: state,
            viewState: viewState,
            alertPresenter: alertPresenter,
            wasShowingLowUsageAlert: wasShowingLowUsageAlert
        )
    }

    private static func lowUsageDesktopNotificationRequestIfNeeded(
        state: AccountPoolState,
        viewState: PoolDashboardViewState,
        alertPresenter: PoolDashboardAlertPresenter = PoolDashboardAlertPresenter(),
        wasShowingLowUsageAlert: Bool
    ) -> DashboardNotificationRequest? {
        guard state.lowUsageAlertsEnabled else { return nil }
        guard !wasShowingLowUsageAlert, viewState.showLowUsageAlert else { return nil }

        let message = viewState.lowUsageAlertMessage
            ?? alertPresenter.lowUsageAlertMessage(
                activeAccount: state.activeAccount,
                thresholdRatio: state.lowUsageAlertThresholdRatio
            )
        return DashboardNotificationRequest(
            key: "low-usage-alert",
            title: "Codex Pool \(L10n.text("alert.low_usage.title"))",
            body: message,
            minInterval: 60
        )
    }

    private func intelligentRemainingRatio(for account: AgentAccount) -> Double {
        account.smartSwitchRemainingRatio
    }

    // MARK: - Account Actions

    private func handleAddAccount(name: String, quota: Int) {
        guard let output = Self.addAccountHandlingOutput(
            state: state,
            formState: formState,
            selectedGroupName: selectedGroupName,
            name: name,
            quota: quota
        ) else {
            return
        }

        state = output.state
        formState = output.formState
    }

    private static func addAccountHandlingOutput(
        state: AccountPoolState,
        formState: PoolDashboardFormState,
        selectedGroupName: String,
        name: String,
        quota: Int
    ) -> AddAccountHandlingOutput? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return nil }

        var updatedState = state
        var updatedFormState = formState
        updatedState.addAccount(
            name: normalizedName,
            groupName: selectedGroupName,
            quota: quota
        )
        updatedFormState.resetNewAccountInput()
        return AddAccountHandlingOutput(
            state: updatedState,
            formState: updatedFormState
        )
    }

    private func handleRemoveAccount(accountID: UUID) {
        applyQuickAction(.removeAccount(accountID))
        store.removeToken(for: accountID)
    }

    private func handleMoveAccount(accountID: UUID, to groupName: String) {
        _ = state.duplicateAccount(accountID, intoGroup: groupName)
    }

    private func handleCreateGroup(name: String) {
        if let created = state.createGroup(name) {
            selectedGroupName = created
        }
    }

    private func handleRenameGroup(from oldName: String, to newName: String) {
        state.renameGroup(from: oldName, to: newName)
        selectedGroupName = AgentAccount.normalizedGroupName(newName)
    }

    private func handleDeleteGroup(name: String) {
        guard let output = Self.deleteGroupHandlingOutput(
            state: state,
            selectedGroupName: selectedGroupName,
            name: name
        ) else {
            return
        }

        state = output.state
        output.removedAccountIDs.forEach { store.removeToken(for: $0) }
        selectedGroupName = output.selectedGroupName
    }

    private static func deleteGroupHandlingOutput(
        state: AccountPoolState,
        selectedGroupName: String,
        name: String
    ) -> DeleteGroupHandlingOutput? {
        let normalized = AgentAccount.normalizedGroupName(name)
        var updatedState = state
        let removedAccountIDs = updatedState.accounts
            .filter { $0.groupName == normalized }
            .map(\.id)
        guard updatedState.deleteGroup(normalized) else { return nil }

        let updatedSelectedGroupName: String
        if selectedGroupName == normalized {
            updatedSelectedGroupName = AgentAccount.defaultGroupName
        } else {
            updatedSelectedGroupName = selectedGroupName
        }

        return DeleteGroupHandlingOutput(
            state: updatedState,
            selectedGroupName: updatedSelectedGroupName,
            removedAccountIDs: removedAccountIDs
        )
    }

    private func handleSimulateUsage() {
        applyQuickAction(.simulateUsage(PoolDashboardQuickActionsFlowCoordinator.defaultSimulatedUsageUnits))
    }

    private func handleEvaluateSwitch() {
        applyQuickAction(.evaluateSwitch)
    }

    private func handleClearActivities() {
        applyQuickAction(.clearActivities)
    }

    private func handleResetAllUsage() {
        let output = quickActionsFlowCoordinator.triggerResetAllUsage(
            from: state,
            resetAllLatch: resetAllLatch
        )
        applyResetAllUsageOutput(output)
    }

    private func applyQuickAction(_ action: PoolDashboardQuickActionsFlowCoordinator.Action) {
        state = quickActionsFlowCoordinator.apply(action, to: state)
    }

    private func applyResetAllUsageOutput(
        _ output: PoolDashboardQuickActionsFlowCoordinator.ResetAllUsageOutput
    ) {
        state = output.state
        resetAllLatch = output.resetAllLatch
    }

    // MARK: - Backup

    private func exportSnapshot() {
        backupFlowCoordinator.exportSnapshot(from: state, viewState: &viewState)
    }

    private func exportRefetchableSnapshot() {
        backupFlowCoordinator.exportRefetchableSnapshot(from: state, viewState: &viewState)
    }

    private func importSnapshot() {
        let shouldSyncUsage = backupFlowCoordinator.importSnapshot(
            state: &state,
            viewState: &viewState
        )
        if shouldSyncUsage {
            Task { await syncCodexUsage() }
        }
    }

    private func applyLifecycleOnAppearOutput(
        _ output: PoolDashboardLifecycleFlowCoordinator.OnAppearOutput
    ) {
        viewMutationCoordinator.applyLifecycleOnAppearOutput(
            output,
            state: &state,
            lowUsageAlertPolicy: &lowUsageAlertPolicy,
            viewModel: &localOAuthImportViewModel,
            sessionAuthorizedAuthFileURL: &sessionAuthorizedAuthFileURL
        )
    }

    private func applyLifecycleSnapshotChangeOutput(
        _ output: PoolDashboardLifecycleFlowCoordinator.SnapshotChangeOutput
    ) {
        viewMutationCoordinator.applyLifecycleSnapshotChangeOutput(
            output,
            lowUsageAlertPolicy: &lowUsageAlertPolicy,
            viewState: &viewState
        )
    }

    private func applyUsageSyncOutput(_ output: PoolDashboardUsageSyncFlowCoordinator.Output) {
        viewMutationCoordinator.applyUsageSyncOutput(
            output,
            state: &state,
            viewState: &viewState
        )
    }

    private func applyOAuthSignInOutput(_ output: PoolDashboardOAuthSignInFlowCoordinator.Output) {
        viewMutationCoordinator.applyOAuthSignInOutput(
            output,
            state: &state,
            viewState: &viewState,
            formState: &formState
        )
    }

    private var intelligentCandidateName: String? {
        guard let candidateID = state.intelligentCandidateID else { return nil }
        return state.accounts.first(where: { $0.id == candidateID })?.name
    }

    // MARK: - Usage Sync

    @MainActor
    private func runDashboardAutoSyncTask() async {
        guard runtimeModel == nil else { return }
        guard state.autoSyncEnabled else { return }
        await syncCodexUsage()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(state.autoSyncIntervalSeconds * 1_000_000_000))
            if Task.isCancelled { break }
            await syncCodexUsage()
        }
    }

    @MainActor
    private func runAppUpdateAutoCheckTask() async {
        guard appUpdateAutoCheckEnabled else { return }
        await checkForAppUpdates(force: false, bypassCadence: true)
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: AppUpdateAutoCheckPolicy.intervalNanoseconds)
            if Task.isCancelled { break }
            await checkForAppUpdates(force: false)
        }
    }

    @MainActor
    private func syncCodexUsage() async {
        if let runtimeModel {
            guard asyncStateCoordinator.beginUsageSync(viewState: &viewState) else { return }
            let runID = UUID()
            usageSyncRunID = runID
            scheduleUsageSyncStuckRecovery(for: runID)
            defer {
                if usageSyncRunID == runID {
                    usageSyncRunID = nil
                    asyncStateCoordinator.endUsageSync(viewState: &viewState)
                }
            }

            let outcome = await syncRuntimeCodexUsageWithTimeout(runtimeModel)
            guard usageSyncRunID == runID else { return }
            if let outcome {
                await handleRuntimeSyncOutcome(outcome)
            }
            return
        }

        guard asyncStateCoordinator.beginUsageSync(viewState: &viewState) else { return }
        let runID = UUID()
        usageSyncRunID = runID
        scheduleUsageSyncStuckRecovery(for: runID)
        defer {
            if usageSyncRunID == runID {
                usageSyncRunID = nil
                asyncStateCoordinator.endUsageSync(viewState: &viewState)
            }
        }

        let previousMode = state.mode
        let previousActiveAccountID = state.activeAccountID
        let previousSyncError = viewState.syncError

        let output = await syncCodexUsageWithTimeout(
            from: state,
            viewState: viewState
        )
        guard usageSyncRunID == runID else { return }
        applyUsageSyncOutput(output)
        if viewState.syncError?.isEmpty ?? true {
            evaluateSpecialResetWatchAfterSync(now: .now)
            updateUsageAnalyticsAfterSync(now: .now)
        }
        if let syncError = viewState.syncError, !syncError.isEmpty {
            DesktopNotifier.post(
                key: "usage-sync-error",
                title: "Codex Pool 同步失敗",
                body: "\(syncError)\n\n\(notificationUsageSummary(for: state.activeAccount))",
                minInterval: 300
            )
        } else if previousSyncError != nil {
            DesktopNotifier.post(
                key: "usage-sync-recovered",
                title: "Codex Pool 已恢復同步",
                body: notificationUsageSummary(for: state.activeAccount),
                minInterval: 60
            )
        }

        await triggerAutomaticSwitchActionIfNeeded(
            previousMode: previousMode,
            previousActiveAccountID: previousActiveAccountID
        )
    }

    @MainActor
    private func handleRuntimeSyncOutcome(_ outcome: AppPoolRuntimeModel.SyncOutcome) async {
        guard lastHandledRuntimeSyncOutcomeID != outcome.id else { return }
        lastHandledRuntimeSyncOutcomeID = outcome.id

        guard outcome.status != .staleDiscard else { return }

        viewState.syncError = outcome.syncError
        if !outcome.outputViewState.lastUsageRawJSON.isEmpty {
            viewState.lastUsageRawJSON = outcome.outputViewState.lastUsageRawJSON
        }

        if let syncError = outcome.syncError, !syncError.isEmpty {
            DesktopNotifier.post(
                key: "usage-sync-error",
                title: "Codex Pool 同步失敗",
                body: "\(syncError)\n\n\(notificationUsageSummary(for: state.activeAccount))",
                minInterval: 300
            )
            return
        }

        guard outcome.stateApplied else { return }
        let wasShowingLowUsageAlert = viewState.showLowUsageAlert
        applyRuntimeStateUpdate(outcome.resultingState)
        showLowUsageAlertForThresholdTriggeredIntelligentSwitch(
            previousSnapshot: outcome.previousState.snapshot,
            currentSnapshot: outcome.resultingState.snapshot
        )
        postLowUsageDesktopNotificationIfNeeded(
            wasShowingLowUsageAlert: wasShowingLowUsageAlert
        )

        if outcome.previousSyncError != nil {
            DesktopNotifier.post(
                key: "usage-sync-recovered",
                title: "Codex Pool 已恢復同步",
                body: notificationUsageSummary(for: state.activeAccount),
                minInterval: 60
            )
        }

        evaluateSpecialResetWatchAfterSync(now: .now)
        updateUsageAnalyticsAfterSync(now: .now)
        await triggerAutomaticSwitchActionIfNeeded(
            previousMode: outcome.previousState.mode,
            previousActiveAccountID: outcome.previousState.activeAccountID
        )
    }

    @MainActor
    private func syncRuntimeCodexUsageWithTimeout(
        _ runtimeModel: AppPoolRuntimeModel
    ) async -> AppPoolRuntimeModel.SyncOutcome? {
        await runtimeModel.syncNowWithTimeout(
            timeoutNanoseconds: SyncPolicy.timeoutNanoseconds,
            timeoutErrorMessage: runtimeSyncTimeoutErrorMessage()
        )
    }

    private func runtimeSyncTimeoutErrorMessage() -> String {
        L10n.text(
            "sync.failure.with_description_format",
            L10n.text("sync.failure.prefix"),
            L10n.text("usage.sync.error.timeout")
        )
    }

    @MainActor
    private func retrySyncCodexUsage() async {
        await syncCodexUsage()
    }

    @MainActor
    private func forceRetrySyncCodexUsage() async {
        if viewState.isSyncingUsage {
            usageSyncRunID = nil
            asyncStateCoordinator.endUsageSync(viewState: &viewState)
        }
        await syncCodexUsage()
    }

    @MainActor
    private func scheduleUsageSyncStuckRecovery(for runID: UUID) {
        Task {
            try? await Task.sleep(nanoseconds: SyncPolicy.stuckRecoveryNanoseconds)
            forceEndUsageSyncIfStuck(runID: runID)
        }
    }

    @MainActor
    private func forceEndUsageSyncIfStuck(runID: UUID) {
        guard let output = Self.usageSyncStuckRecoveryOutput(
            runID: runID,
            currentRunID: usageSyncRunID,
            viewState: viewState,
            asyncStateCoordinator: asyncStateCoordinator
        ) else {
            return
        }
        viewState = output.viewState
        usageSyncRunID = output.usageSyncRunID
    }

    private static func usageSyncStuckRecoveryOutput(
        runID: UUID,
        currentRunID: UUID?,
        viewState: PoolDashboardViewState,
        asyncStateCoordinator: PoolDashboardAsyncStateCoordinator = PoolDashboardAsyncStateCoordinator()
    ) -> (viewState: PoolDashboardViewState, usageSyncRunID: UUID?)? {
        guard currentRunID == runID, viewState.isSyncingUsage else { return nil }

        var nextViewState = viewState
        nextViewState.syncError = L10n.text(
            "sync.failure.with_description_format",
            L10n.text("sync.failure.prefix"),
            L10n.text("usage.sync.error.timeout")
        )
        asyncStateCoordinator.endUsageSync(viewState: &nextViewState)
        return (nextViewState, nil)
    }

    @MainActor
    private func syncCodexUsageWithTimeout(
        from state: AccountPoolState,
        viewState: PoolDashboardViewState
    ) async -> PoolDashboardUsageSyncFlowCoordinator.Output {
        let timeoutErrorMessage = L10n.text(
            "sync.failure.with_description_format",
            L10n.text("sync.failure.prefix"),
            L10n.text("usage.sync.error.timeout")
        )

        return await withTaskGroup(of: PoolDashboardUsageSyncFlowCoordinator.Output.self) { group in
            group.addTask {
                await usageSyncFlowCoordinator.syncCodexUsage(
                    from: state,
                    viewState: viewState
                )
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: SyncPolicy.timeoutNanoseconds)
                var timedOutViewState = viewState
                timedOutViewState.syncError = timeoutErrorMessage
                return PoolDashboardUsageSyncFlowCoordinator.Output(
                    state: state,
                    viewState: timedOutViewState
                )
            }

            let firstOutput = await group.next() ?? PoolDashboardUsageSyncFlowCoordinator.Output(
                state: state,
                viewState: viewState
            )
            group.cancelAll()
            return firstOutput
        }
    }

    // MARK: - OAuth

    @MainActor
    private func signInWithOAuth() async {
        pendingManualOAuthContext = nil
        manualOAuthCallbackURL = ""

        guard asyncStateCoordinator.beginOAuthSignIn(viewState: &viewState) else { return }
        defer { asyncStateCoordinator.endOAuthSignIn(viewState: &viewState) }

        let output = await oauthSignInFlowCoordinator.signInWithOAuth(
            from: state,
            viewState: viewState,
            oauthAccountName: formState.oauthAccountName,
            input: .init(
                issuer: oauthIssuer,
                clientID: oauthClientID,
                scopes: oauthScopes,
                redirectURI: oauthRedirectURI,
                originator: oauthOriginator,
                workspaceID: oauthWorkspaceID,
                fallbackQuota: formState.oauthAccountQuota
            )
        )
        guard !Task.isCancelled else { return }
        applyOAuthSignInOutput(output)
        if output.shouldRefreshLocalOAuthAccounts {
            refreshLocalOAuthAccounts()
            Task { @MainActor in
                await syncCodexUsage()
            }
        }
    }

    @MainActor
    private func prepareManualOAuthSignIn() {
        let output = oauthSignInFlowCoordinator.prepareManualOAuthSignIn(
            input: .init(
                issuer: oauthIssuer,
                clientID: oauthClientID,
                scopes: oauthScopes,
                redirectURI: oauthRedirectURI,
                originator: oauthOriginator,
                workspaceID: oauthWorkspaceID,
                fallbackQuota: formState.oauthAccountQuota
            )
        )

        guard let authorizationURL = output.authorizationURL,
              let expectedState = output.expectedState,
              let codeVerifier = output.codeVerifier else {
            viewState.oauthError = output.oauthError ?? L10n.text("oauth.error.invalid_authorize_url")
            viewState.oauthSuccessMessage = nil
            return
        }

        pendingManualOAuthContext = PendingManualOAuthContext(
            expectedState: expectedState,
            codeVerifier: codeVerifier,
            authorizationURL: authorizationURL
        )
        copyTextToClipboard(authorizationURL.absoluteString)
        viewState.oauthError = nil
        viewState.oauthSuccessMessage = L10n.text("oauth.manual.copy_success")
    }

    @MainActor
    private func importManualOAuthCallback() async {
        guard let pendingManualOAuthContext else {
            viewState.oauthError = L10n.text("oauth.error.invalid_callback")
            viewState.oauthSuccessMessage = nil
            return
        }

        guard asyncStateCoordinator.beginOAuthSignIn(viewState: &viewState) else { return }
        defer { asyncStateCoordinator.endOAuthSignIn(viewState: &viewState) }

        let output = await oauthSignInFlowCoordinator.importManualOAuthCallback(
            from: state,
            viewState: viewState,
            oauthAccountName: formState.oauthAccountName,
            input: .init(
                issuer: oauthIssuer,
                clientID: oauthClientID,
                scopes: oauthScopes,
                redirectURI: oauthRedirectURI,
                originator: oauthOriginator,
                workspaceID: oauthWorkspaceID,
                fallbackQuota: formState.oauthAccountQuota
            ),
            callbackURLString: manualOAuthCallbackURL,
            expectedState: pendingManualOAuthContext.expectedState,
            codeVerifier: pendingManualOAuthContext.codeVerifier
        )
        guard !Task.isCancelled else { return }
        applyOAuthSignInOutput(output)
        if output.shouldRefreshLocalOAuthAccounts {
            refreshLocalOAuthAccounts()
            manualOAuthCallbackURL = ""
            self.pendingManualOAuthContext = nil
            Task { @MainActor in
                await syncCodexUsage()
            }
        }
    }

    @MainActor
    private func startOAuthTask(_ operation: @escaping @MainActor () async -> Void) {
        guard oauthSignInTask == nil else { return }
        oauthSignInTask = Task { @MainActor in
            await operation()
            oauthSignInTask = nil
        }
    }

    @MainActor
    private func cancelOAuthSignIn() {
        oauthSignInTask?.cancel()
        oauthSignInTask = nil
        viewState.isSigningInOAuth = false
    }

    @MainActor
    private func addRelayAccount() {
        Task { @MainActor in
            await performAddRelayAccount()
        }
    }

    @MainActor
    private func performAddRelayAccount() async {
        let output = await relayAccountCoordinator.addRelayAccount(
            to: state,
            viewState: viewState,
            name: formState.relayAccountName,
            providerID: formState.relayProviderID,
            providerName: formState.relayProviderName,
            baseURL: formState.relayBaseURL,
            wireAPI: formState.relayWireAPI,
            apiKey: formState.relayAPIKey
        )
        state = output.state
        viewState = output.viewState
        if viewState.relayError == nil {
            // Persist immediately so the new relay API key is in the token vault
            // before the user can switch to it. The snapshot-driven autosave is
            // async, so without this an immediate switch resolves the key from a
            // vault that hasn't been written yet and fails with "missing API key".
            store.save(state.snapshot)
            formState.resetRelayInput()
            refreshRelayAPIKeyReadiness()
        }
    }

    private func copyTextToClipboard(_ text: String) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }

    // MARK: - Local Accounts

    private func refreshLocalOAuthAccounts() {
        let output = localAccountsFlowCoordinator.refreshLocalOAuthAccounts(
            from: state,
            viewModel: localOAuthImportViewModel,
            authFileAccessService: authFileAccessService,
            currentAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL
        )
        _ = applyAndReturnPickedAuthFileURL(output)
    }

    @MainActor
    @discardableResult
    private func openAuthFilePanel() -> URL? {
        let output = localAccountsFlowCoordinator.openAuthFilePanel(
            from: state,
            viewModel: localOAuthImportViewModel,
            currentAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL,
            authFileAccessService: authFileAccessService
        )
        return applyAndReturnPickedAuthFileURL(output)
    }

    private func applyAndReturnPickedAuthFileURL(
        _ output: PoolDashboardLocalAccountsFlowCoordinator.Output
    ) -> URL? {
        viewMutationCoordinator.applyLocalAccountsOutput(
            output,
            state: &state,
            viewModel: &localOAuthImportViewModel,
            sessionAuthorizedAuthFileURL: &sessionAuthorizedAuthFileURL
        )
    }

    private func applyLocalImportOutput(_ output: PoolDashboardLocalImportFlowCoordinator.Output) {
        viewMutationCoordinator.applyLocalImportOutput(
            output,
            state: &state,
            viewModel: &localOAuthImportViewModel,
            viewState: &viewState
        )
    }

    private func applySwitchLaunchOutput(_ output: PoolDashboardSwitchLaunchFlowCoordinator.Output) {
        viewMutationCoordinator.applySwitchLaunchOutput(
            output,
            viewModel: &localOAuthImportViewModel,
            viewState: &viewState,
            sessionAuthorizedAuthFileURL: &sessionAuthorizedAuthFileURL
        )
    }

    @MainActor
    private func triggerAutomaticSwitchActionIfNeeded(
        previousMode: SwitchMode,
        previousActiveAccountID: UUID?
    ) async {
        guard previousMode == .intelligent, state.mode == .intelligent else { return }
        guard let currentActiveAccountID = state.activeAccountID,
              currentActiveAccountID != previousActiveAccountID,
              let account = state.accounts.first(where: { $0.id == currentActiveAccountID })
        else {
            return
        }

        let output = await switchLaunchFlowCoordinator.switchAndLaunch(
            using: account,
            switchWithoutLaunching: state.switchWithoutLaunching,
            launchTarget: selectedLaunchTarget,
            currentAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL,
            authFileAccessService: authFileAccessService,
            viewModel: localOAuthImportViewModel,
            viewState: viewState,
            authorizeAuthFile: openAuthFilePanel
        )
        let decision = automaticSwitchDecision(
            account: account,
            previousActiveAccountID: previousActiveAccountID,
            output: output
        )
        if let accountIDToMark = decision.accountIDToMarkForSwitchLaunch {
            suppressNextSnapshotDrivenSwitch = true
            state.markActiveAccountForSwitchLaunch(accountIDToMark)
        }
        if let notification = decision.notification {
            DesktopNotifier.post(
                key: notification.key,
                title: notification.title,
                body: notification.body,
                minInterval: notification.minInterval
            )
        }
        applySwitchLaunchOutput(output)
    }

    private func automaticSwitchDecision(
        account: AgentAccount,
        previousActiveAccountID: UUID?,
        output: PoolDashboardSwitchLaunchFlowCoordinator.Output
    ) -> AutomaticSwitchDecision {
        if output.didSwitchAuth {
            return AutomaticSwitchDecision(
                accountIDToMarkForSwitchLaunch: account.id,
                notification: DashboardNotificationRequest(
                    key: "auto-switch-\(account.id.uuidString)",
                    title: "Codex Pool 已自動切換帳號",
                    body: notificationUsageSummary(
                        for: state.accounts.first(where: { $0.id == account.id }) ?? account
                    ),
                    minInterval: 15
                )
            )
        }

        guard let previousActiveAccountID,
              state.accounts.contains(where: { $0.id == previousActiveAccountID }) else {
            return AutomaticSwitchDecision(
                accountIDToMarkForSwitchLaunch: nil,
                notification: nil
            )
        }

        let errorMessage = output.viewState.switchLaunchError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let notification = errorMessage.isEmpty ? nil : DashboardNotificationRequest(
            key: "auto-switch-failed",
            title: "Codex Pool 自動切換失敗",
            body: errorMessage,
            minInterval: 120
        )
        return AutomaticSwitchDecision(
            accountIDToMarkForSwitchLaunch: previousActiveAccountID,
            notification: notification
        )
    }

    @MainActor
    private func importLocalOAuthAccount(_ localAccount: LocalCodexOAuthAccount) async {
        guard importingLocalOAuthAccountID == nil else { return }
        importingLocalOAuthAccountID = localAccount.id
        defer { importingLocalOAuthAccountID = nil }

        let output = await localImportFlowCoordinator.importLocalOAuthAccount(
            localAccount,
            from: state,
            viewModel: localOAuthImportViewModel,
            viewState: viewState,
            onRawResponse: { raw in
                viewState.lastUsageRawJSON = raw
            }
        )
        applyLocalImportOutput(output)
        if output.didImport {
            Task { @MainActor in
                await syncCodexUsage()
            }
        }
    }

    // MARK: - Switch & Launch

    @MainActor
    private func switchAndLaunchCodex(using accountID: UUID) async {
        let account: AgentAccount
        switch manualSwitchRoute(for: accountID) {
        case .missing:
            return
        case .relay:
            await switchToRelayProvider(using: accountID)
            return
        case let .official(officialAccount):
            account = officialAccount
        }

        let output = await switchLaunchFlowCoordinator.switchAndLaunch(
            using: account,
            switchWithoutLaunching: state.switchWithoutLaunching,
            launchTarget: selectedLaunchTarget,
            currentAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL,
            authFileAccessService: authFileAccessService,
            viewModel: localOAuthImportViewModel,
            viewState: viewState,
            authorizeAuthFile: openAuthFilePanel
        )
        let decision = manualSwitchDecision(account: account, output: output)
        if let accountIDToMark = decision.accountIDToMarkForSwitchLaunch {
            suppressNextSnapshotDrivenSwitch = true
            state.markActiveAccountForSwitchLaunch(accountIDToMark)
        }
        if let notification = decision.notification {
            DesktopNotifier.post(
                key: notification.key,
                title: notification.title,
                body: notification.body,
                minInterval: notification.minInterval
            )
        }
        applySwitchLaunchOutput(output)
    }

    private func manualSwitchRoute(for accountID: UUID) -> ManualSwitchRoute {
        guard let account = state.accounts.first(where: { $0.id == accountID }) else {
            return .missing
        }
        return account.isRelayAPIKeyAccount ? .relay : .official(account)
    }

    private func manualSwitchDecision(
        account: AgentAccount,
        output: PoolDashboardSwitchLaunchFlowCoordinator.Output
    ) -> ManualSwitchDecision {
        if output.didSwitchAuth {
            return ManualSwitchDecision(
                accountIDToMarkForSwitchLaunch: account.id,
                notification: DashboardNotificationRequest(
                    key: "manual-switch-\(account.id.uuidString)",
                    title: "Codex Pool 已切換帳號",
                    body: notificationUsageSummary(
                        for: state.accounts.first(where: { $0.id == account.id }) ?? account
                    ),
                    minInterval: 5
                )
            )
        }

        guard let errorMessage = output.viewState.switchLaunchError,
              !errorMessage.isEmpty else {
            return ManualSwitchDecision(
                accountIDToMarkForSwitchLaunch: nil,
                notification: nil
            )
        }

        return ManualSwitchDecision(
            accountIDToMarkForSwitchLaunch: nil,
            notification: DashboardNotificationRequest(
                key: "manual-switch-failed",
                title: "Codex Pool 切換失敗",
                body: errorMessage,
                minInterval: 120
            )
        )
    }

    @MainActor
    private func switchToRelayProvider(using accountID: UUID) async {
        let preparation = prepareRelaySwitchRequest(for: accountID)
        guard let request = preparation.request else {
            let errorDescription = preparation.errorDescription ?? L10n.text("relay.error.invalid_provider")
            viewState.switchLaunchError = errorDescription
            viewState.switchLaunchWarning = nil
            viewState.lastSwitchLaunchLog = [
                preparation.diagnosticLog,
                L10n.text("relay.switch.start_format", preparation.requestAccountName),
                L10n.text("relay.switch.failed_format", errorDescription)
            ].joined(separator: "\n")
            DesktopNotifier.post(
                key: "manual-relay-switch-failed",
                title: "Codex Pool 中轉切換失敗",
                body: errorDescription,
                minInterval: 120
            )
            return
        }

        let output = await relayAccountCoordinator.switchToRelayAccount(
            request,
            switchWithoutLaunching: state.switchWithoutLaunching,
            preserveOfficialAuth: relayPreserveOfficialAuth,
            launchTarget: selectedLaunchTarget,
            diagnosticLog: preparation.diagnosticLog,
            viewState: viewState
        )
        viewState = output.viewState

        let decision = relaySwitchOutcomeDecision(request: request, output: output)
        if let accountIDToMark = decision.accountIDToMarkForSwitchLaunch {
            suppressNextSnapshotDrivenSwitch = true
            state.markActiveAccountForSwitchLaunch(accountIDToMark)
        }
        if let notification = decision.notification {
            DesktopNotifier.post(
                key: notification.key,
                title: notification.title,
                body: notification.body,
                minInterval: notification.minInterval
            )
        }
    }

    private func relaySwitchOutcomeDecision(
        request: PoolDashboardRelayAccountCoordinator.SwitchRequest,
        output: PoolDashboardRelayAccountCoordinator.SwitchOutput
    ) -> RelaySwitchOutcomeDecision {
        if output.didSwitchAuth {
            return RelaySwitchOutcomeDecision(
                accountIDToMarkForSwitchLaunch: request.accountID,
                notification: DashboardNotificationRequest(
                    key: "manual-relay-switch-\(request.accountID.uuidString)",
                    title: "Codex Pool 已切換中轉帳號",
                    body: state.accounts
                        .first(where: { $0.id == request.accountID })
                        .map(notificationUsageSummary(for:)) ?? request.accountName,
                    minInterval: 5
                )
            )
        }

        guard let errorMessage = output.viewState.switchLaunchError,
              !errorMessage.isEmpty else {
            return RelaySwitchOutcomeDecision(
                accountIDToMarkForSwitchLaunch: nil,
                notification: nil
            )
        }

        return RelaySwitchOutcomeDecision(
            accountIDToMarkForSwitchLaunch: nil,
            notification: DashboardNotificationRequest(
                key: "manual-relay-switch-failed",
                title: "Codex Pool 中轉切換失敗",
                body: errorMessage,
                minInterval: 120
            )
        )
    }

    @MainActor
    private func prepareRelaySwitchRequest(for accountID: UUID) -> RelaySwitchPreparation {
        let request: PoolDashboardRelayAccountCoordinator.SwitchRequest
        let stateAccountCount = state.accounts.count
        let relayAccountCount = state.accounts.filter(\.isRelayAPIKeyAccount).count
        let fallbackAPIKey = store.apiToken(for: accountID)
        let initialAccount = state.accounts.first(where: { $0.id == accountID })
        let initialSnapshotAPIKeyLength = relayDiagnosticTokenLength(initialAccount?.apiToken)
        let vaultAPIKeyLength = relayDiagnosticTokenLength(fallbackAPIKey)
        var hydratedFromVault = false
        var diagnosticLog = ""
        var requestAccountName = L10n.text("account.unknown")
        do {
            request = try {
                if state.accounts
                    .first(where: { $0.id == accountID })?
                    .apiToken
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty == true {
                    hydratedFromVault = state.hydrateMissingAPIToken(for: accountID, token: fallbackAPIKey)
                    if !hydratedFromVault,
                       let loadedSnapshot = store.load() {
                        hydratedFromVault = state.hydrateMissingAPITokens(from: loadedSnapshot)
                    }
                }
                guard let account = state.accounts.first(where: { $0.id == accountID }) else {
                    throw CodexProviderConfigError.invalidProviderID
                }
                requestAccountName = account.name
                return try PoolDashboardRelayAccountCoordinator.SwitchRequest(
                    account: account,
                    fallbackAPIKey: fallbackAPIKey
                )
            }()
            diagnosticLog = RelaySwitchDiagnostic(
                stage: "prepared",
                accountID: accountID,
                account: state.accounts.first(where: { $0.id == accountID }),
                stateAccountCount: stateAccountCount,
                relayAccountCount: relayAccountCount,
                snapshotAPIKeyLength: initialSnapshotAPIKeyLength,
                vaultAPIKeyLength: vaultAPIKeyLength,
                hydratedFromVault: hydratedFromVault,
                requestAPIKeyLength: request.apiKey.count,
                requestAPIKeyDataLength: request.apiKeyData.count,
                preserveOfficialAuth: relayPreserveOfficialAuth,
                switchWithoutLaunching: state.switchWithoutLaunching,
                launchTarget: selectedLaunchTarget,
                selectedAuthMethod: selectedAuthMethodRaw,
                storeType: String(describing: type(of: store)),
                appVersion: appVersionText(),
                appBuild: appBuildText()
            ).renderedLog()
        } catch {
            diagnosticLog = RelaySwitchDiagnostic(
                stage: "prepare_failed",
                accountID: accountID,
                account: state.accounts.first(where: { $0.id == accountID }) ?? initialAccount,
                stateAccountCount: stateAccountCount,
                relayAccountCount: relayAccountCount,
                snapshotAPIKeyLength: initialSnapshotAPIKeyLength,
                vaultAPIKeyLength: vaultAPIKeyLength,
                hydratedFromVault: hydratedFromVault,
                requestAPIKeyLength: nil,
                requestAPIKeyDataLength: nil,
                preserveOfficialAuth: relayPreserveOfficialAuth,
                switchWithoutLaunching: state.switchWithoutLaunching,
                launchTarget: selectedLaunchTarget,
                selectedAuthMethod: selectedAuthMethodRaw,
                storeType: String(describing: type(of: store)),
                appVersion: appVersionText(),
                appBuild: appBuildText(),
                errorStage: "switch_request",
                errorDescription: error.localizedDescription
            ).renderedLog()
            return RelaySwitchPreparation(
                request: nil,
                diagnosticLog: diagnosticLog,
                requestAccountName: requestAccountName,
                errorDescription: error.localizedDescription,
                hydratedFromVault: hydratedFromVault
            )
        }

        return RelaySwitchPreparation(
            request: request,
            diagnosticLog: diagnosticLog,
            requestAccountName: requestAccountName,
            errorDescription: nil,
            hydratedFromVault: hydratedFromVault
        )
    }

    private func relayDiagnosticTokenLength(_ token: String?) -> Int {
        token?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
    }

    // MARK: - Special Reset Watch

    private func loadSpecialResetWatchStateFromStorage() {
        guard !specialResetWatchStateRaw.isEmpty,
              let data = specialResetWatchStateRaw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(SpecialResetWatchState.self, from: data)
        else {
            specialResetWatchState = SpecialResetWatchState()
            return
        }
        var normalizedState = decoded
        normalizedState.records = deduplicatedSpecialResetRecords(decoded.records)
        specialResetWatchState = normalizedState
    }

    private func persistSpecialResetWatchState() {
        guard let data = try? JSONEncoder().encode(specialResetWatchState),
              let text = String(data: data, encoding: .utf8)
        else {
            return
        }
        specialResetWatchStateRaw = text
    }

    @MainActor
    private func resetSpecialResetWatchBaseline(now: Date = .now) {
        let baselineState = specialResetBaselineWatchState(accounts: state.accounts, now: now)
        specialResetWatchState.records = baselineState.records
        specialResetWatchState.events = baselineState.events
        specialResetWatchState.lastEvaluatedAt = baselineState.lastEvaluatedAt
        persistSpecialResetWatchState()
    }

    private func specialResetBaselineWatchState(
        accounts: [AgentAccount],
        now: Date
    ) -> SpecialResetWatchState {
        let baselineRecords = accounts
            .filter(\.isPaid)
            .map { account in
                SpecialResetRecord(
                    accountKey: specialResetWatchAccountKey(for: account),
                    accountName: normalizedSpecialResetAccountName(account),
                    expectedWeeklyResetAt: normalizedExpectedResetDate(
                        observedResetAt: account.secondaryUsageResetAt ?? account.usageWindowResetAt,
                        kind: .weekly,
                        now: now
                    ),
                    expectedFiveHourResetAt: normalizedExpectedResetDate(
                        observedResetAt: account.primaryUsageResetAt,
                        kind: .fiveHour,
                        now: now
                    ),
                    lastObservedWeeklyResetAt: account.secondaryUsageResetAt ?? account.usageWindowResetAt,
                    lastObservedFiveHourResetAt: account.primaryUsageResetAt,
                    lastSeenWeeklyUsagePercent: specialResetWeeklyUsagePercent(for: account),
                    lastSeenUsedUnits: account.usedUnits,
                    lastSeenFiveHourUsagePercent: account.primaryUsagePercent,
                    lastSeenAt: now
                )
            }
        var baselineState = SpecialResetWatchState()
        baselineState.records = deduplicatedSpecialResetRecords(baselineRecords)
        baselineState.events = []
        baselineState.lastEvaluatedAt = now
        return baselineState
    }

    @MainActor
    private func clearSpecialResetWatchEvents() {
        specialResetWatchState.events = []
        persistSpecialResetWatchState()
    }

    @MainActor
    private func evaluateSpecialResetWatchAfterSync(now: Date) {
        guard specialResetWatchEnabled else { return }
        guard let output = specialResetEvaluationOutput(
            currentState: specialResetWatchState,
            accounts: state.accounts,
            now: now,
            graceMinutes: specialResetWatchGraceMinutes,
            notificationsEnabled: specialResetWatchNotifyEnabled
        ) else {
            return
        }

        specialResetWatchState = output.state
        if output.shouldNotify {
            postSpecialResetDetections(output.detections)
        }

        persistSpecialResetWatchState()
    }

    private func specialResetEvaluationOutput(
        currentState: SpecialResetWatchState,
        accounts: [AgentAccount],
        now: Date,
        graceMinutes: Int,
        notificationsEnabled: Bool
    ) -> SpecialResetEvaluationOutput? {
        let paidAccounts = accounts.filter(\.isPaid)
        guard !paidAccounts.isEmpty else { return nil }

        let graceSeconds = TimeInterval(max(0, graceMinutes) * 60)
        var recordsByKey = specialResetRecordsByKey(from: currentState.records)
        var detections: [SpecialResetDetection] = []

        for account in paidAccounts {
            let accountKey = specialResetWatchAccountKey(for: account)
            var record = recordsByKey[accountKey] ?? SpecialResetRecord(
                accountKey: accountKey,
                accountName: normalizedSpecialResetAccountName(account)
            )
            record.accountName = normalizedSpecialResetAccountName(account)

            let weeklyExpectedAt = record.expectedWeeklyResetAt
            let observedWeeklyResetAt = account.secondaryUsageResetAt ?? account.usageWindowResetAt
            record.expectedWeeklyResetAt = normalizedExpectedResetDate(
                observedResetAt: observedWeeklyResetAt,
                kind: .weekly,
                now: now
            )

            let fiveHourExpectedAt = record.expectedFiveHourResetAt
            let observedFiveHourResetAt = account.primaryUsageResetAt
            let weeklyUsagePercent = specialResetWeeklyUsagePercent(for: account)
            let fiveHourUsagePercent = specialResetFiveHourUsagePercent(for: account)
            if let combinedSignal = SpecialResetAlertEvaluator.detectCombinedEarlyReset(
                weeklyExpectedResetAt: weeklyExpectedAt,
                observedWeeklyResetAt: observedWeeklyResetAt,
                fiveHourExpectedResetAt: fiveHourExpectedAt,
                observedFiveHourResetAt: observedFiveHourResetAt,
                previousWeeklyUsagePercent: record.lastSeenWeeklyUsagePercent,
                previousFiveHourUsagePercent: record.lastSeenFiveHourUsagePercent,
                weeklyUsagePercent: weeklyUsagePercent,
                fiveHourUsagePercent: fiveHourUsagePercent,
                now: now,
                graceSeconds: graceSeconds,
                previousObservedWeeklyResetAt: record.lastObservedWeeklyResetAt,
                previousObservedFiveHourResetAt: record.lastObservedFiveHourResetAt
            ) {
                detections.append(
                    SpecialResetDetection(
                        accountKey: accountKey,
                        accountName: normalizedSpecialResetAccountName(account),
                        previousWeeklyExpectedAt: combinedSignal.weekly.previousExpectedAt,
                        observedWeeklyNextResetAt: combinedSignal.weekly.observedNextResetAt,
                        previousFiveHourExpectedAt: combinedSignal.fiveHour.previousExpectedAt,
                        observedFiveHourNextResetAt: combinedSignal.fiveHour.observedNextResetAt,
                        detectedAt: now
                    )
                )
            }
            record.expectedFiveHourResetAt = normalizedExpectedResetDate(
                observedResetAt: observedFiveHourResetAt,
                kind: .fiveHour,
                now: now
            )

            record.lastSeenWeeklyUsagePercent = weeklyUsagePercent
            record.lastSeenUsedUnits = account.usedUnits
            record.lastSeenFiveHourUsagePercent = fiveHourUsagePercent
            record.lastObservedWeeklyResetAt = observedWeeklyResetAt
            record.lastObservedFiveHourResetAt = observedFiveHourResetAt
            record.lastSeenAt = now
            recordsByKey[accountKey] = record
        }

        let activeAccountKeys = Set(paidAccounts.map { specialResetWatchAccountKey(for: $0) })
        var nextState = currentState
        nextState.records = recordsByKey
            .filter { activeAccountKeys.contains($0.key) }
            .map(\.value)
            .sorted(by: { $0.accountName.localizedCaseInsensitiveCompare($1.accountName) == .orderedAscending })
        nextState.lastEvaluatedAt = now
        var shouldNotify = false

        if !detections.isEmpty {
            let newEvents = detections.map { detection in
                SpecialResetEvent(
                    id: UUID(),
                    detectedAt: detection.detectedAt,
                    accountKey: detection.accountKey,
                    accountName: detection.accountName,
                    previousWeeklyExpectedAt: detection.previousWeeklyExpectedAt,
                    observedWeeklyNextResetAt: detection.observedWeeklyNextResetAt,
                    previousFiveHourExpectedAt: detection.previousFiveHourExpectedAt,
                    observedFiveHourNextResetAt: detection.observedFiveHourNextResetAt
                )
            }
            nextState.events = Array((newEvents + nextState.events).prefix(40))
            if notificationsEnabled,
               SpecialResetNotificationPolicy.shouldNotify(
                   lastNotifiedAt: nextState.lastNotificationAt,
                   now: now
               ) {
                shouldNotify = true
                nextState.lastNotificationAt = now
            }
        }

        return SpecialResetEvaluationOutput(
            state: nextState,
            detections: detections,
            shouldNotify: shouldNotify
        )
    }

    private func specialResetRecordsByKey(from records: [SpecialResetRecord]) -> [String: SpecialResetRecord] {
        records.reduce(into: [String: SpecialResetRecord]()) { partial, record in
            partial[record.accountKey] = record
        }
    }

    private func deduplicatedSpecialResetRecords(_ records: [SpecialResetRecord]) -> [SpecialResetRecord] {
        specialResetRecordsByKey(from: records)
            .values
            .sorted(by: { $0.accountName.localizedCaseInsensitiveCompare($1.accountName) == .orderedAscending })
    }

    private func normalizedExpectedResetDate(
        observedResetAt: Date?,
        kind: SpecialResetKind,
        now: Date
    ) -> Date? {
        SpecialResetAlertEvaluator.normalizedExpectedResetDate(
            observedResetAt: observedResetAt,
            interval: kind.interval,
            now: now
        )
    }

    private func normalizedSpecialResetAccountName(_ account: AgentAccount) -> String {
        let trimmed = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.text("account.unknown") : trimmed
    }

    private func specialResetDisplayedResetDates(
        for record: SpecialResetRecord
    ) -> (weekly: String, fiveHour: String) {
        if let account = state.accounts.first(where: { $0.isPaid && specialResetWatchAccountKey(for: $0) == record.accountKey }) {
            return (
                (account.secondaryUsageResetAt ?? account.usageWindowResetAt)
                    .map(specialResetDateText) ?? L10n.text("schedule.summary.not_available"),
                account.primaryUsageResetAt.map(specialResetDateText) ?? L10n.text("schedule.summary.not_available")
            )
        }

        return (
            record.expectedWeeklyResetAt.map(specialResetDateText) ?? L10n.text("schedule.summary.not_available"),
            record.expectedFiveHourResetAt.map(specialResetDateText) ?? L10n.text("schedule.summary.not_available")
        )
    }

    private func postSpecialResetDetections(_ detections: [SpecialResetDetection]) {
        guard let request = specialResetDetectionNotificationRequest(detections) else { return }
        DesktopNotifier.post(
            key: request.key,
            title: request.title,
            body: request.body,
            minInterval: request.minInterval
        )
    }

    private func specialResetDetectionNotificationRequest(
        _ detections: [SpecialResetDetection]
    ) -> DashboardNotificationRequest? {
        guard let detection = detections.first else { return nil }
        let body = L10n.text(
            "special_reset.notification.body_format",
            detection.accountName,
            specialResetDateText(detection.previousWeeklyExpectedAt),
            specialResetDateText(detection.observedWeeklyNextResetAt),
            specialResetDateText(detection.previousFiveHourExpectedAt),
            specialResetDateText(detection.observedFiveHourNextResetAt)
        )
        return DashboardNotificationRequest(
            key: "special-reset-daily",
            title: L10n.text("special_reset.notification.title"),
            body: body,
            minInterval: 30
        )
    }

    private func specialResetEventMessage(for event: SpecialResetEvent) -> String {
        L10n.text(
            "special_reset.event.message_format",
            event.accountName,
            specialResetDateText(event.previousWeeklyExpectedAt),
            specialResetDateText(event.observedWeeklyNextResetAt),
            specialResetDateText(event.previousFiveHourExpectedAt),
            specialResetDateText(event.observedFiveHourNextResetAt),
            specialResetDateText(event.detectedAt)
        )
    }

    // MARK: - App Update

    @MainActor
    private func checkForAppUpdates(force: Bool, bypassCadence: Bool = false) async {
        guard !isCheckingForAppUpdate else { return }
        if !force && !appUpdateAutoCheckEnabled { return }
        if !force && !bypassCadence && !shouldRunAutomaticUpdateCheck(now: .now) { return }

        isCheckingForAppUpdate = true
        if force {
            appUpdateStatusMessage = L10n.text("update.checking")
        }

        defer {
            isCheckingForAppUpdate = false
        }

        appUpdateLastCheckedAt = Date().timeIntervalSince1970

        do {
            let release = try await appUpdateService.fetchLatestRelease(
                languageOverrideCode: appLanguageOverride,
                includePrerelease: isPrereleaseUpdateChannelEnabled
            )
            let currentVersion = appVersionText()
            let latestVersion = release.normalizedVersion
            guard AppUpdateVersioning.isRemoteNewer(
                current: currentVersion,
                remote: latestVersion
            ) else {
                appUpdateAvailablePrompt = nil
                if force {
                    appUpdateStatusMessage = L10n.text("update.status.up_to_date_format", currentVersion)
                }
                return
            }

            if !force, appUpdateSkippedVersion == latestVersion {
                appUpdateAvailablePrompt = nil
                return
            }

            let prompt = AppUpdatePrompt(
                currentVersion: currentVersion,
                latestVersion: latestVersion,
                release: release
            )
            appUpdateAvailablePrompt = prompt
            appUpdatePrompt = prompt
            appUpdateStatusMessage = L10n.text("update.status.new_version_format", latestVersion)
        } catch {
            if force {
                appUpdateStatusMessage = L10n.text("update.status.failure_format", error.localizedDescription)
            }
        }
    }

    private func shouldRunAutomaticUpdateCheck(now: Date) -> Bool {
        AppUpdateAutoCheckPolicy.shouldRun(lastCheckedAt: appUpdateLastCheckedAt, now: now)
    }

    private func appVersionText() -> String {
        let shortVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
        return AppUpdateVersioning.normalizedVersion(from: shortVersion)
    }

    private func appBuildText() -> String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
    }

    private var isPrereleaseUpdateChannelEnabled: Bool {
        AppUpdateChannel.isPrereleaseEnabled
    }

    private func appUpdatePublishedText(_ date: Date?) -> String {
        guard let date else { return L10n.text("update.not_available") }
        return date.formatted(
            .dateTime
                .locale(L10n.locale())
                .year()
                .month()
                .day()
                .hour()
                .minute()
        )
    }

    private func dismissAppUpdatePrompt() {
        appUpdatePrompt = nil
    }

    private func skipAppUpdateVersion(_ prompt: AppUpdatePrompt) {
        appUpdateSkippedVersion = prompt.latestVersion
        appUpdateStatusMessage = L10n.text("update.status.skipped_format", prompt.latestVersion)
        appUpdateAvailablePrompt = nil
        dismissAppUpdatePrompt()
    }

    private func openManualAppUpdateDownload(_ prompt: AppUpdatePrompt) {
        openExternalURL(prompt.release.htmlURL)
        appUpdateStatusMessage = L10n.text("update.status.opened_manual")
    }

    private func downloadAppUpdateNow(_ prompt: AppUpdatePrompt) {
        if sparkleUpdateDriver.startUserInitiatedUpdate() {
            appUpdateStatusMessage = L10n.text("update.status.sparkle_started")
            dismissAppUpdatePrompt()
            appUpdateAvailablePrompt = nil
            return
        }

        appUpdateStatusMessage = L10n.text("update.status.direct_unavailable")
    }

    private func currentWhatsNewAnnouncement() -> WhatsNewAnnouncement {
        WhatsNewAnnouncement.current(version: appVersionText(), build: appBuildText())
    }

    private func showWhatsNewIfNeeded() {
        let announcement = currentWhatsNewAnnouncement()
        guard WhatsNewPromptPolicy.shouldShow(
            currentVersionID: announcement.id,
            lastSeenVersionID: whatsNewLastSeenVersionID
        ) else {
            return
        }

        whatsNewPrompt = announcement
    }

    private func showWhatsNewManually() {
        whatsNewPrompt = currentWhatsNewAnnouncement()
    }

    private func dismissWhatsNewReminder() {
        whatsNewPrompt = nil
    }

    private func markWhatsNewSeen(_ announcement: WhatsNewAnnouncement) {
        whatsNewLastSeenVersionID = announcement.id
        whatsNewPrompt = nil
    }

    private func openExternalURL(_ url: URL) {
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }

    @ViewBuilder
    private func appUpdateOverlay(prompt: AppUpdatePrompt) -> some View {
        ZStack {
            Color.black.opacity(PoolDashboardTheme.isLightPalette ? 0.2 : 0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissAppUpdatePrompt()
                }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("update.prompt.title_format", prompt.latestVersion))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(PoolDashboardTheme.textPrimary)
                        Text(L10n.text("update.prompt.subtitle_format", prompt.currentVersion))
                            .font(.subheadline)
                            .foregroundStyle(PoolDashboardTheme.textSecondary)
                    }

                    Spacer(minLength: 0)

                    Button {
                        dismissAppUpdatePrompt()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(PoolDashboardTheme.textSecondary)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(PoolDashboardTheme.panelMutedFill)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }

                Text(
                    L10n.text("update.prompt.published_format", appUpdatePublishedText(prompt.release.publishedAt))
                )
                .font(.caption)
                .foregroundStyle(PoolDashboardTheme.textMuted)

                HStack(spacing: 8) {
                    Button(L10n.text("update.prompt.skip")) {
                        skipAppUpdateVersion(prompt)
                    }
                    .buttonStyle(.bordered)

                    Button(L10n.text("update.prompt.manual")) {
                        openManualAppUpdateDownload(prompt)
                    }
                    .buttonStyle(.bordered)

                    Button(L10n.text("update.prompt.install_now")) {
                        downloadAppUpdateNow(prompt)
                    }
                    .buttonStyle(DashboardWarningButtonStyle())
                }

                Text(L10n.text("update.prompt.install_note"))
                    .font(.caption)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("update.prompt.release_format", prompt.release.displayTitle))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PoolDashboardTheme.textPrimary)

                    Text(L10n.text("update.prompt.notes_title"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PoolDashboardTheme.textSecondary)

                    if let releaseNotes = prompt.release.releaseNotesText {
                        ScrollView(.vertical, showsIndicators: true) {
                            Text(verbatim: releaseNotes)
                                .font(.caption)
                                .foregroundStyle(PoolDashboardTheme.textMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 170)
                    } else {
                        Text(L10n.text("update.prompt.notes_unavailable"))
                            .font(.caption)
                            .foregroundStyle(PoolDashboardTheme.textMuted)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 640, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PoolDashboardTheme.modalSolidFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(PoolDashboardTheme.glowA.opacity(0.35), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 16)
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private func whatsNewOverlay(announcement: WhatsNewAnnouncement) -> some View {
        ZStack {
            Color.black.opacity(PoolDashboardTheme.isLightPalette ? 0.2 : 0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissWhatsNewReminder()
                }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(announcement.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(PoolDashboardTheme.textPrimary)
                        Text(announcement.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(PoolDashboardTheme.textSecondary)
                    }

                    Spacer(minLength: 0)

                    Button {
                        dismissWhatsNewReminder()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(PoolDashboardTheme.textSecondary)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(PoolDashboardTheme.panelMutedFill)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }

                ForEach(announcement.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PoolDashboardTheme.textPrimary)

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(section.bodyLines, id: \.self) { line in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Circle()
                                        .fill(PoolDashboardTheme.glowA)
                                        .frame(width: 5, height: 5)
                                    Text(line)
                                        .font(.callout)
                                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(PoolDashboardTheme.panelMutedFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: 1)
                            )
                    )
                }

                HStack(spacing: 8) {
                    Button(L10n.text("whats_new.later")) {
                        dismissWhatsNewReminder()
                    }
                    .buttonStyle(.bordered)

                    Button(L10n.text("whats_new.dismiss")) {
                        markWhatsNewSeen(announcement)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PoolDashboardTheme.glowA)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(16)
            .frame(maxWidth: 560, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PoolDashboardTheme.modalSolidFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(PoolDashboardTheme.glowA.opacity(0.35), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 16)
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    // MARK: - Usage Analytics

    private var selectedWorkspaceUsesUsageAnalytics: Bool {
        selectedWorkspace == .schedule || selectedWorkspace == .usageAnalytics
    }

    private func ensureUsageAnalyticsStateLoadedIfNeeded() {
        guard selectedWorkspaceUsesUsageAnalytics else { return }
        ensureUsageAnalyticsStateLoaded()
    }

    private func ensureUsageAnalyticsStateLoaded() {
        guard !usageAnalyticsStateLoaded else { return }
        loadUsageAnalyticsStateFromStorage()
    }

    private func releaseUsageAnalyticsStateIfPossible() {
        guard !selectedWorkspaceUsesUsageAnalytics else { return }
        usageAnalyticsState = UsageAnalyticsState()
        usageAnalyticsStateLoaded = false
    }

    private func loadUsageAnalyticsStateFromStorage() {
        guard let output = Self.normalizedStoredUsageAnalyticsPayload(
            rawValue: usageAnalyticsStateRaw,
            accounts: state.accounts,
            maxStoredRecords: normalizedUsageAnalyticsMaxStoredRecords,
            now: .now
        ) else {
            usageAnalyticsState = UsageAnalyticsState()
            usageAnalyticsStateLoaded = true
            return
        }
        usageAnalyticsState = output.normalizedState
        usageAnalyticsStateLoaded = true
        if let rewrittenRawValue = output.rewrittenRawValue {
            usageAnalyticsStateRaw = rewrittenRawValue
        }
    }

    private func persistUsageAnalyticsState() {
        usageAnalyticsState = UsageAnalyticsEngine.normalized(
            state: usageAnalyticsState,
            accounts: state.accounts,
            now: .now,
            maxStoredRecords: normalizedUsageAnalyticsMaxStoredRecords
        )
        guard let data = try? JSONEncoder().encode(usageAnalyticsState),
              let text = String(data: data, encoding: .utf8)
        else {
            return
        }
        usageAnalyticsStateRaw = text
    }

    private var normalizedUsageAnalyticsMaxStoredRecords: Int {
        UsageAnalyticsEngine.clampedMaxStoredRecords(usageAnalyticsMaxStoredRecords)
    }

    private func normalizeStoredUsageAnalyticsForCurrentLimit() {
        guard let output = Self.normalizedStoredUsageAnalyticsPayload(
            rawValue: usageAnalyticsStateRaw,
            accounts: state.accounts,
            maxStoredRecords: normalizedUsageAnalyticsMaxStoredRecords,
            now: .now
        ) else { return }

        if usageAnalyticsStateLoaded {
            usageAnalyticsState = output.normalizedState
        }
        if let rewrittenRawValue = output.rewrittenRawValue {
            usageAnalyticsStateRaw = rewrittenRawValue
        }
    }

    private static func normalizedStoredUsageAnalyticsPayload(
        rawValue: String,
        accounts: [AgentAccount],
        maxStoredRecords: Int,
        now: Date
    ) -> UsageAnalyticsStorageNormalizationOutput? {
        guard !rawValue.isEmpty,
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(UsageAnalyticsState.self, from: data)
        else {
            return nil
        }
        let normalized = UsageAnalyticsEngine.normalized(
            state: decoded,
            accounts: accounts,
            now: now,
            maxStoredRecords: maxStoredRecords
        )
        let rewrittenRawValue: String?
        if normalized != decoded,
           let normalizedData = try? JSONEncoder().encode(normalized),
           let text = String(data: normalizedData, encoding: .utf8) {
            rewrittenRawValue = text
        } else {
            rewrittenRawValue = nil
        }
        return UsageAnalyticsStorageNormalizationOutput(
            normalizedState: normalized,
            rewrittenRawValue: rewrittenRawValue
        )
    }

    private func clearUsageAnalyticsIdleDelay(accountKey: String?) {
        ensureUsageAnalyticsStateLoaded()
        usageAnalyticsState = Self.usageAnalyticsStateClearingIdleDelay(
            usageAnalyticsState,
            accountKey: accountKey
        )
        persistUsageAnalyticsState()
    }

    private static func usageAnalyticsStateClearingIdleDelay(
        _ state: UsageAnalyticsState,
        accountKey: String?
    ) -> UsageAnalyticsState {
        var updated = state
        updated.records = updated.records.map { record in
            guard accountKey == nil || record.accountKey == accountKey else {
                return record
            }
            guard record.weeklyIdleDelayMinutes > 0 else {
                return record
            }
            return UsageAnalyticsRecord(
                id: record.id,
                timestamp: record.timestamp,
                accountKey: record.accountKey,
                weeklyDeltaPercent: record.weeklyDeltaPercent,
                fiveHourDeltaPercent: record.fiveHourDeltaPercent,
                weeklyAbsolutePercent: record.weeklyAbsolutePercent,
                fiveHourAbsolutePercent: record.fiveHourAbsolutePercent,
                weeklyRemainingPercent: record.weeklyRemainingPercent,
                fiveHourRemainingPercent: record.fiveHourRemainingPercent,
                weeklyWastedPercent: record.weeklyWastedPercent,
                fiveHourWastedPercent: record.fiveHourWastedPercent,
                weeklyIdleDelayMinutes: 0,
                weeklyResetAt: record.weeklyResetAt,
                fiveHourResetAt: record.fiveHourResetAt,
                activeAccountKeyAtSync: record.activeAccountKeyAtSync
            )
        }
        return updated
    }

    @MainActor
    @discardableResult
    private func seedUsageAnalyticsIfNeeded(now: Date = .now) -> Bool {
        guard usageAnalyticsStateLoaded else { return false }
        guard usageAnalyticsState.snapshots.isEmpty else { return false }
        usageAnalyticsState = UsageAnalyticsEngine.seed(
            state: usageAnalyticsState,
            accounts: state.accounts,
            activeAccountKey: state.activeAccount?.usageAnalyticsAccountKey,
            now: now
        )
        persistUsageAnalyticsState()
        return true
    }

    @MainActor
    @discardableResult
    private func updateUsageAnalyticsAfterSync(now: Date) -> Bool {
        guard usageAnalyticsStateLoaded || selectedWorkspaceUsesUsageAnalytics else { return false }
        ensureUsageAnalyticsStateLoaded()
        usageAnalyticsState = UsageAnalyticsEngine.update(
            state: usageAnalyticsState,
            accounts: state.accounts,
            activeAccountKey: state.activeAccount?.usageAnalyticsAccountKey,
            now: now,
            maxStoredRecords: normalizedUsageAnalyticsMaxStoredRecords
        )
        persistUsageAnalyticsState()
        return true
    }

    private func specialResetDateText(_ date: Date) -> String {
        date.formatted(.dateTime.locale(L10n.locale()).month().day().hour().minute())
    }

    private func specialResetWeeklyUsagePercent(for account: AgentAccount) -> Int? {
        if let weeklyPercent = account.secondaryUsagePercent {
            return max(0, min(100, weeklyPercent))
        }
        if account.isPaid {
            return nil
        }
        guard account.quota > 0 else { return nil }
        let ratio = Double(account.usedUnits) / Double(account.quota)
        return max(0, min(100, Int((ratio * 100).rounded())))
    }

    private func specialResetWatchAccountKey(for account: AgentAccount) -> String {
        "id:\(account.id.uuidString.lowercased())"
    }

    private func specialResetFiveHourUsagePercent(for account: AgentAccount) -> Int? {
        guard let fiveHourPercent = account.primaryUsagePercent else { return nil }
        return max(0, min(100, fiveHourPercent))
    }

    private func notificationUsageSummary(for account: AgentAccount?) -> String {
        guard let account else {
            return "目前沒有啟用帳號。"
        }

        var lines: [String] = []
        lines.append("帳號：\(account.name)")
        lines.append("剩餘：\(account.remainingUnits)/\(account.quota)")

        if account.isPaid {
            if let primaryUsagePercent = account.primaryUsagePercent {
                let fiveHourRemaining = max(0, min(100, 100 - primaryUsagePercent))
                lines.append("5h 剩餘：\(fiveHourRemaining)%")
            } else {
                lines.append("5h 剩餘：--")
            }
            lines.append("週重置：\(notificationDateText(account.usageWindowResetAt))")
            lines.append("5h 重置：\(notificationDateText(account.primaryUsageResetAt))")
        } else {
            lines.append("重置：\(notificationDateText(account.usageWindowResetAt))")
        }

        return lines.joined(separator: "\n")
    }

    private func notificationDateText(_ date: Date?) -> String {
        guard let date else { return "--" }
        return date.formatted(.dateTime.locale(L10n.locale()).month().day().hour().minute())
    }
}

enum AppUpdateError: LocalizedError, Equatable {
    case invalidResponse
    case decodingFailed
    case noPrereleaseAvailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid update response."
        case .decodingFailed:
            return "Failed to decode update metadata."
        case .noPrereleaseAvailable:
            return "No prerelease update is available."
        }
    }
}

enum AppUpdateChannel {
    static let prereleaseUpdatesEnabledKey = "pool_dashboard.prerelease_updates_enabled"

    static var isPrereleaseEnabled: Bool {
        UserDefaults.standard.bool(forKey: prereleaseUpdatesEnabledKey)
    }

    static func sparkleFeedAssetName(for architecture: AppUpdateArchitecture) -> String {
        let prefix = isPrereleaseEnabled ? "appcast-dev" : "appcast"
        switch architecture {
        case .appleSilicon:
            return "\(prefix)-arm64.xml"
        case .intel:
            return "\(prefix)-x86_64.xml"
        case .unknown:
            return "\(prefix)-arm64.xml"
        }
    }
}

struct WhatsNewAnnouncementSection: Equatable, Identifiable {
    let id: String
    let title: String
    let bodyLines: [String]
}

struct WhatsNewAnnouncement: Equatable, Identifiable {
    let id: String
    let displayVersion: String
    let title: String
    let subtitle: String
    let sections: [WhatsNewAnnouncementSection]

    static func current(version: String, build: String) -> WhatsNewAnnouncement {
        let displayVersion = AppUpdateVersioning.normalizedVersion(from: version)
        return WhatsNewAnnouncement(
            id: WhatsNewPromptPolicy.versionID(version: displayVersion, build: build),
            displayVersion: displayVersion,
            title: L10n.text("whats_new.title_format", displayVersion),
            subtitle: L10n.text("whats_new.subtitle"),
            sections: [
                WhatsNewAnnouncementSection(
                    id: "reset-credit-main-account-card",
                    title: L10n.text("whats_new.reset_credit.title"),
                    bodyLines: [
                        L10n.text("whats_new.reset_credit.body"),
                        L10n.text("whats_new.reset_credit.full_mode"),
                        L10n.text("whats_new.reset_credit.compact_mode")
                    ]
                )
            ]
        )
    }
}

enum WhatsNewPromptPolicy {
    static func versionID(version: String, build: String) -> String {
        let normalizedVersion = AppUpdateVersioning.normalizedVersion(from: version)
        let trimmedBuild = build.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBuild.isEmpty else {
            return normalizedVersion
        }
        return "\(normalizedVersion)+\(trimmedBuild)"
    }

    static func shouldShow(currentVersionID: String, lastSeenVersionID: String) -> Bool {
        let current = currentVersionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return false }
        let lastSeen = lastSeenVersionID.trimmingCharacters(in: .whitespacesAndNewlines)
        return current != lastSeen
    }
}

enum AppUpdateArchitecture: Equatable {
    case appleSilicon
    case intel
    case unknown

    static var current: AppUpdateArchitecture {
        #if arch(arm64)
        .appleSilicon
        #elseif arch(x86_64)
        .intel
        #else
        .unknown
        #endif
    }
}

struct AppUpdateAsset: Equatable {
    let name: String
    let downloadURL: URL
}

struct AppUpdateRelease: Equatable {
    let tagName: String
    let name: String
    let htmlURL: URL
    let publishedAt: Date?
    let body: String?
    let assets: [AppUpdateAsset]
    let notesLanguageCode: String?

    init(
        tagName: String,
        name: String,
        htmlURL: URL,
        publishedAt: Date?,
        body: String? = nil,
        assets: [AppUpdateAsset],
        notesLanguageCode: String? = nil
    ) {
        self.tagName = tagName
        self.name = name
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
        self.body = body
        self.assets = assets
        self.notesLanguageCode = notesLanguageCode
    }

    var normalizedVersion: String {
        AppUpdateVersioning.normalizedVersion(from: tagName)
    }

    var displayTitle: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? tagName : trimmedName
    }

    var releaseNotesText: String? {
        guard let body else { return nil }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func replacingReleaseNotes(_ text: String, languageCode: String?) -> AppUpdateRelease {
        AppUpdateRelease(
            tagName: tagName,
            name: name,
            htmlURL: htmlURL,
            publishedAt: publishedAt,
            body: text,
            assets: assets,
            notesLanguageCode: languageCode
        )
    }

    var buildMatrixLines: [String] {
        let dmgAssets = assets.filter { $0.name.lowercased().hasSuffix(".dmg") }
        if dmgAssets.isEmpty { return [] }
        return dmgAssets.map { asset in
            let lowercased = asset.name.lowercased()
            if lowercased.contains("apple-silicon") || lowercased.contains("arm64") || lowercased.contains("aarch64") {
                return "macOS Apple Silicon (arm64)"
            }
            if lowercased.contains("intel") || lowercased.contains("x86_64") {
                return "macOS Intel (x86_64)"
            }
            return asset.name
        }
    }

    func preferredInstallerURL(for architecture: AppUpdateArchitecture) -> URL? {
        let dmgAssets = assets.filter { $0.name.lowercased().hasSuffix(".dmg") }
        guard !dmgAssets.isEmpty else { return nil }

        switch architecture {
        case .appleSilicon:
            if let preferred = dmgAssets.first(where: {
                let lowercased = $0.name.lowercased()
                return lowercased.contains("apple-silicon") || lowercased.contains("arm64") || lowercased.contains("aarch64")
            }) {
                return preferred.downloadURL
            }
        case .intel:
            if let preferred = dmgAssets.first(where: {
                let lowercased = $0.name.lowercased()
                return lowercased.contains("intel") || lowercased.contains("x86_64")
            }) {
                return preferred.downloadURL
            }
        case .unknown:
            break
        }

        return dmgAssets.first?.downloadURL
    }

    func assetForLocalizedReleaseNotes(candidates: [String]) -> (asset: AppUpdateAsset, languageCode: String)? {
        let noteAssets = assets.filter { asset in
            let lowercased = asset.name.lowercased()
            return lowercased.hasSuffix(".md") || lowercased.hasSuffix(".txt")
        }
        guard !noteAssets.isEmpty else { return nil }

        for candidate in candidates {
            for asset in noteAssets where AppUpdateRelease.assetName(asset.name, matchesLanguageCode: candidate) {
                return (asset, candidate)
            }
        }
        return nil
    }

    private static func assetName(_ name: String, matchesLanguageCode languageCode: String) -> Bool {
        let normalizedName = name
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        let normalizedCode = languageCode
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        guard !normalizedCode.isEmpty else { return false }

        let nameTokens = normalizedName.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let codeTokens = normalizedCode.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)

        guard !nameTokens.isEmpty, !codeTokens.isEmpty, nameTokens.count >= codeTokens.count else { return false }
        for start in 0...(nameTokens.count - codeTokens.count) {
            if Array(nameTokens[start..<(start + codeTokens.count)]) == codeTokens {
                return true
            }
        }
        return false
    }
}

enum AppUpdateVersioning {
    static func normalizedVersion(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "0" }
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    static func isRemoteNewer(current: String, remote: String) -> Bool {
        compare(current: current, remote: remote) == .orderedAscending
    }

    static func compare(current: String, remote: String) -> ComparisonResult {
        let currentParts = numericParts(from: normalizedVersion(from: current))
        let remoteParts = numericParts(from: normalizedVersion(from: remote))
        let count = max(currentParts.count, remoteParts.count)

        for index in 0..<count {
            let currentValue = index < currentParts.count ? currentParts[index] : 0
            let remoteValue = index < remoteParts.count ? remoteParts[index] : 0
            if currentValue < remoteValue { return .orderedAscending }
            if currentValue > remoteValue { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func numericParts(from version: String) -> [Int] {
        version
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
    }
}

enum AppUpdateAutoCheckPolicy {
    static let intervalSeconds: TimeInterval = 30 * 60
    static var intervalNanoseconds: UInt64 {
        UInt64(intervalSeconds * 1_000_000_000)
    }

    static func shouldRun(lastCheckedAt: TimeInterval, now: Date) -> Bool {
        guard lastCheckedAt > 0 else { return true }
        return now.timeIntervalSince1970 - lastCheckedAt >= intervalSeconds
    }
}

struct AppUpdateService {
    var endpoint = URL(string: "https://api.github.com/repos/irons163/codex-pool-manager/releases/latest")!
    var session: URLSession = .shared

    func fetchLatestRelease(
        languageOverrideCode: String = "system",
        includePrerelease: Bool = false
    ) async throws -> AppUpdateRelease {
        let requestURL = includePrerelease
            ? releasesListEndpoint(from: endpoint)
            : endpoint
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CodexPoolManager/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppUpdateError.invalidResponse
        }

        let decoder = JSONDecoder()
        do {
            let payload: AppUpdateReleasePayload
            if includePrerelease {
                guard let visibleRelease = try decoder.decode([AppUpdateReleasePayload].self, from: data)
                    .first(where: { $0.isVisibleRelease })
                else {
                    throw AppUpdateError.noPrereleaseAvailable
                }
                payload = visibleRelease
            } else {
                payload = try decoder.decode(AppUpdateReleasePayload.self, from: data)
            }
            let release = payload.release
            if let localizedNotes = try await fetchLocalizedReleaseNotes(
                for: release,
                languageOverrideCode: languageOverrideCode
            ) {
                return release.replacingReleaseNotes(localizedNotes.text, languageCode: localizedNotes.languageCode)
            }
            return release
        } catch {
            if let updateError = error as? AppUpdateError {
                throw updateError
            }
            throw AppUpdateError.decodingFailed
        }
    }

    private func releasesListEndpoint(from latestEndpoint: URL) -> URL {
        guard var components = URLComponents(url: latestEndpoint, resolvingAgainstBaseURL: false) else {
            return latestEndpoint
        }

        components.path = components.path.replacingOccurrences(of: "/releases/latest", with: "/releases")
        components.queryItems = [URLQueryItem(name: "per_page", value: "20")]
        return components.url ?? latestEndpoint
    }

    private func fetchLocalizedReleaseNotes(
        for release: AppUpdateRelease,
        languageOverrideCode: String
    ) async throws -> (text: String, languageCode: String)? {
        let candidates = AppUpdateReleaseNotesLanguageResolver.candidateLanguageCodes(
            languageOverrideCode: languageOverrideCode
        )
        guard !candidates.isEmpty else { return nil }

        guard let match = release.assetForLocalizedReleaseNotes(candidates: candidates) else {
            return nil
        }

        var request = URLRequest(url: match.asset.downloadURL)
        request.httpMethod = "GET"
        request.setValue("CodexPoolManager/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else {
                return nil
            }
            return (text, match.languageCode)
        } catch {
            return nil
        }
    }
}

private enum AppUpdateReleaseNotesLanguageResolver {
    static func candidateLanguageCodes(languageOverrideCode: String) -> [String] {
        let normalizedOverride = L10n.normalizedLanguageOverrideCode(languageOverrideCode)
        let preferred = normalizedOverride == L10n.systemLanguageCode
            ? L10n.locale().identifier
            : normalizedOverride
        let normalizedPreferred = normalize(preferred)
        let basePreferred = normalizedPreferred.split(separator: "-").first.map(String.init) ?? normalizedPreferred

        var ordered: [String] = []
        func append(_ code: String) {
            let normalized = normalize(code)
            guard !normalized.isEmpty, !ordered.contains(normalized) else { return }
            ordered.append(normalized)
        }

        append(normalizedPreferred)
        append(basePreferred)
        append("en")
        return ordered
    }

    static func normalize(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }
}

@MainActor
final class SparkleUpdateDriver: NSObject {
    static let shared = SparkleUpdateDriver()

    #if canImport(Sparkle)
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    var isAvailable: Bool { true }

    func startUserInitiatedUpdate() -> Bool {
        guard updaterController.updater.canCheckForUpdates else { return false }
        updaterController.checkForUpdates(nil)
        return true
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func checkForUpdatesInBackground() {
        updaterController.updater.checkForUpdatesInBackground()
    }
    #else
    var isAvailable: Bool { false }

    func startUserInitiatedUpdate() -> Bool { false }

    func checkForUpdates() {}

    func checkForUpdatesInBackground() {}
    #endif

    private override init() {
        super.init()
    }
}

#if canImport(Sparkle)
extension SparkleUpdateDriver: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        let assetName = AppUpdateChannel.sparkleFeedAssetName(for: AppUpdateArchitecture.current)
        return "https://github.com/irons163/codex-pool-manager/releases/latest/download/\(assetName)"
    }
}
#endif

private struct AppUpdateReleasePayload: Decodable {
    struct AssetPayload: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let name: String
    let htmlURL: URL
    let publishedAtRaw: String?
    let body: String?
    let draft: Bool?
    let prerelease: Bool?
    let assets: [AssetPayload]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case publishedAtRaw = "published_at"
        case body
        case draft
        case prerelease
        case assets
    }

    var isVisibleRelease: Bool {
        draft != true
    }

    var release: AppUpdateRelease {
        AppUpdateRelease(
            tagName: tagName,
            name: name,
            htmlURL: htmlURL,
            publishedAt: parseDate(from: publishedAtRaw),
            body: body,
            assets: assets.map {
                AppUpdateAsset(name: $0.name, downloadURL: $0.browserDownloadURL)
            }
        )
    }

    private func parseDate(from rawValue: String?) -> Date? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: rawValue) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue)
    }
}

enum SpecialResetNotificationPolicy {
    static func shouldNotify(
        lastNotifiedAt: Date?,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard let lastNotifiedAt else { return true }
        return !calendar.isDate(lastNotifiedAt, inSameDayAs: now)
    }
}

enum SpecialResetAlertEvaluator {
    struct TimeSignal: Equatable {
        let previousExpectedAt: Date
        let observedNextResetAt: Date
    }

    static func normalizedExpectedResetDate(
        observedResetAt: Date?,
        interval: TimeInterval,
        now: Date
    ) -> Date? {
        guard var observedResetAt else { return nil }
        var guardSteps = 0
        while observedResetAt <= now, guardSteps < 240 {
            observedResetAt = observedResetAt.addingTimeInterval(interval)
            guardSteps += 1
        }
        return observedResetAt
    }

    static func detectEarlyResetSignal(
        expectedResetAt: Date?,
        observedResetAt: Date?,
        interval: TimeInterval,
        now: Date,
        graceSeconds: TimeInterval
    ) -> TimeSignal? {
        let minimumLeadSeconds: TimeInterval = max(300, graceSeconds)
        let minimumForwardShiftSeconds: TimeInterval = max(1_200, graceSeconds * 2)

        guard let expectedResetAt,
              let observedNextResetAt = normalizedExpectedResetDate(
                observedResetAt: observedResetAt,
                interval: interval,
                now: now
              )
        else {
            return nil
        }

        let isNotDueYet = expectedResetAt.timeIntervalSince(now) > minimumLeadSeconds
        let forwardShiftSeconds = observedNextResetAt.timeIntervalSince(expectedResetAt)
        let isSignificantForwardShift = forwardShiftSeconds >= minimumForwardShiftSeconds
        guard isNotDueYet, isSignificantForwardShift else {
            return nil
        }

        return TimeSignal(
            previousExpectedAt: expectedResetAt,
            observedNextResetAt: observedNextResetAt
        )
    }

    static func detectCombinedEarlyReset(
        weeklyExpectedResetAt: Date?,
        observedWeeklyResetAt: Date?,
        fiveHourExpectedResetAt: Date?,
        observedFiveHourResetAt: Date?,
        previousWeeklyUsagePercent: Int?,
        previousFiveHourUsagePercent: Int?,
        weeklyUsagePercent: Int?,
        fiveHourUsagePercent: Int?,
        now: Date,
        graceSeconds: TimeInterval,
        previousObservedWeeklyResetAt: Date? = nil,
        previousObservedFiveHourResetAt: Date? = nil
    ) -> (weekly: TimeSignal, fiveHour: TimeSignal)? {
        guard let observedWeeklyResetAt, let observedFiveHourResetAt else {
            return nil
        }
        guard isFullyReset(
            previousWeeklyUsagePercent: previousWeeklyUsagePercent,
            previousFiveHourUsagePercent: previousFiveHourUsagePercent,
            weeklyUsagePercent: weeklyUsagePercent,
            fiveHourUsagePercent: fiveHourUsagePercent
        ) else {
            return nil
        }
        guard let weeklySignal = detectEarlyResetSignal(
            expectedResetAt: weeklyExpectedResetAt,
            observedResetAt: observedWeeklyResetAt,
            interval: 7 * 24 * 3_600,
            now: now,
            graceSeconds: graceSeconds
        ),
        let fiveHourSignal = detectEarlyResetSignal(
            expectedResetAt: fiveHourExpectedResetAt,
            observedResetAt: observedFiveHourResetAt,
            interval: 5 * 3_600,
            now: now,
            graceSeconds: graceSeconds
        ) else {
            return nil
        }
        let minimumObservedAdvanceSeconds = max(300, graceSeconds)
        guard observedResetAdvancedSignificantly(
            previousObservedResetAt: previousObservedWeeklyResetAt,
            observedResetAt: observedWeeklyResetAt,
            minimumAdvanceSeconds: minimumObservedAdvanceSeconds
        ),
        observedResetAdvancedSignificantly(
            previousObservedResetAt: previousObservedFiveHourResetAt,
            observedResetAt: observedFiveHourResetAt,
            minimumAdvanceSeconds: minimumObservedAdvanceSeconds
        ) else {
            return nil
        }
        return (weekly: weeklySignal, fiveHour: fiveHourSignal)
    }

    private static func isFullyReset(
        previousWeeklyUsagePercent: Int?,
        previousFiveHourUsagePercent: Int?,
        weeklyUsagePercent: Int?,
        fiveHourUsagePercent: Int?
    ) -> Bool {
        guard let weeklyUsagePercent, let fiveHourUsagePercent else { return false }
        guard weeklyUsagePercent == 0 && fiveHourUsagePercent == 0 else { return false }

        // Require at least one usage window to transition from non-zero to zero.
        // This avoids false positives when an account has been idle at 0% for a long time.
        let weeklyTransitioned = (previousWeeklyUsagePercent ?? 0) > 0
        let fiveHourTransitioned = (previousFiveHourUsagePercent ?? 0) > 0
        return weeklyTransitioned || fiveHourTransitioned
    }

    private static func observedResetAdvancedSignificantly(
        previousObservedResetAt: Date?,
        observedResetAt: Date,
        minimumAdvanceSeconds: TimeInterval
    ) -> Bool {
        guard let previousObservedResetAt else { return true }
        return observedResetAt.timeIntervalSince(previousObservedResetAt) >= minimumAdvanceSeconds
    }
}

private struct ScheduleWorkspacePanelView: View {
    private enum Horizon: Int, CaseIterable, Identifiable {
        case next24Hours = 24
        case next72Hours = 72
        case next7Days = 168

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .next24Hours:
                return L10n.text("schedule.horizon.24h")
            case .next72Hours:
                return L10n.text("schedule.horizon.72h")
            case .next7Days:
                return L10n.text("schedule.horizon.7d")
            }
        }
    }

    private enum ResetKind {
        case weekly
        case fiveHour

        var title: String {
            switch self {
            case .weekly:
                return L10n.text("schedule.events.weekly")
            case .fiveHour:
                return L10n.text("schedule.events.five_hour")
            }
        }

        var badgeTone: Color {
            switch self {
            case .weekly:
                return PoolDashboardTheme.warning.opacity(0.20)
            case .fiveHour:
                return PoolDashboardTheme.glowA.opacity(0.25)
            }
        }
    }

    private struct ResetEvent: Identifiable {
        let id = UUID()
        let accountID: UUID
        let accountName: String
        let date: Date
        let kind: ResetKind
    }

    private struct CoverageSlot: Identifiable {
        let start: Date
        let end: Date
        let events: [ResetEvent]
        let trackedAccountCount: Int
        let resettingAccountIDs: Set<UUID>

        var id: Date { start }
        var resettingAccountCount: Int { resettingAccountIDs.count }
        var availableAccountCount: Int {
            max(0, trackedAccountCount - resettingAccountCount)
        }
        var hasCoverage: Bool { availableAccountCount > 0 }
    }

    private struct CoverageRow: Identifiable {
        let slots: [CoverageSlot]
        var id: Date { slots.first?.start ?? .distantPast }
    }

    private struct GapRange: Identifiable {
        let start: Date
        let end: Date

        var id: Date { start }
    }

    private struct Timeline {
        let events: [ResetEvent]
        let slots: [CoverageSlot]
        let rows: [CoverageRow]
        let gaps: [GapRange]

        var coveredHours: Int {
            slots.filter(\.hasCoverage).count
        }

        var noCoverageHours: Int {
            slots.filter { !$0.hasCoverage }.count
        }

        var overlapHours: Int {
            slots.filter { $0.resettingAccountCount > 1 }.count
        }

        var coveragePercent: Int {
            guard !slots.isEmpty else { return 0 }
            return Int((Double(coveredHours) / Double(slots.count) * 100).rounded())
        }
    }

    @AppStorage("pool_dashboard.schedule.horizon_hours")
    private var persistedHorizonHours = Horizon.next72Hours.rawValue

    let accounts: [AgentAccount]

    private var selectedHorizon: Horizon {
        Horizon(rawValue: persistedHorizonHours) ?? .next72Hours
    }

    private var horizonBinding: Binding<Horizon> {
        Binding(
            get: { selectedHorizon },
            set: { persistedHorizonHours = $0.rawValue }
        )
    }

    private var timeline: Timeline {
        let start = Calendar.autoupdatingCurrent.dateInterval(of: .hour, for: .now)?.start ?? .now
        let end = start.addingTimeInterval(TimeInterval(selectedHorizon.rawValue) * 3_600)
        let events = buildEvents(from: start, to: end)
        let trackedAccountIDs = Set(events.map(\.accountID))
        let slots = buildSlots(
            from: start,
            hours: selectedHorizon.rawValue,
            events: events,
            trackedAccountCount: trackedAccountIDs.count
        )
        let rows = stride(from: 0, to: slots.count, by: 24).map { index in
            CoverageRow(slots: Array(slots[index..<min(index + 24, slots.count)]))
        }
        let gaps = buildGapRanges(from: slots)
        return Timeline(events: events, slots: slots, rows: rows, gaps: gaps)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                headerRow

                if accounts.isEmpty {
                    PanelStatusCalloutView(
                        message: L10n.text("schedule.empty_accounts.message"),
                        title: L10n.text("schedule.empty_accounts.title"),
                        tone: .info
                    )
                } else if timeline.events.isEmpty {
                    PanelStatusCalloutView(
                        message: L10n.text("schedule.empty_resets.message"),
                        title: L10n.text("schedule.empty_resets.title"),
                        tone: .warning
                    )
                } else {
                    summaryCards
                    coverageChart
                    coverageLegend
                    coverageGapSummary
                    upcomingEvents
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(L10n.text("workspace.schedule.title"))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(PoolDashboardTheme.textPrimary.opacity(PoolDashboardTheme.groupLabelOpacity))

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Text(L10n.text("schedule.horizon.title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textSecondary)

                Picker("", selection: horizonBinding) {
                    ForEach(Horizon.allCases) { horizon in
                        Text(horizon.title).tag(horizon)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 230)
            }
        }
    }

    private var summaryCards: some View {
        HStack(alignment: .top, spacing: 8) {
            summaryCard(
                title: L10n.text("schedule.summary.coverage_hours"),
                value: "\(timeline.coveredHours)/\(timeline.slots.count) (\(timeline.coveragePercent)%)"
            )
            summaryCard(
                title: L10n.text("schedule.summary.no_coverage_hours"),
                value: "\(timeline.noCoverageHours)"
            )
            summaryCard(
                title: L10n.text("schedule.summary.overlap_hours"),
                value: "\(timeline.overlapHours)"
            )
            summaryCard(
                title: L10n.text("schedule.summary.next_reset"),
                value: timeline.events.first.map { localizedMonthDayHourMinuteText($0.date) } ?? L10n.text("schedule.summary.not_available")
            )
        }
    }

    private func summaryCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PoolDashboardTheme.textMuted)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PoolDashboardTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardInfoCard()
    }

    private var coverageChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(timeline.rows) { row in
                HStack(alignment: .center, spacing: 8) {
                    Text(coverageRowLabel(for: row))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                        .frame(width: 140, alignment: .leading)

                    HStack(spacing: 2) {
                        ForEach(row.slots) { slot in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(fillColor(for: slot))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .stroke(PoolDashboardTheme.panelInnerStroke.opacity(0.45), lineWidth: 0.6)
                                )
                                .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14)
                        }
                    }
                }
            }
        }
        .dashboardInfoCard()
    }

    private var coverageLegend: some View {
        HStack(spacing: 10) {
            legendItem(color: fullCoverageColor, title: L10n.text("schedule.legend.covered"))
            legendItem(color: partialCoverageColor, title: L10n.text("schedule.legend.overlap"))
            legendItem(color: noCoverageColor, title: L10n.text("schedule.legend.uncovered"))
        }
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(PoolDashboardTheme.panelInnerStroke.opacity(0.5), lineWidth: 0.6)
                )
            Text(title)
                .font(.caption)
                .foregroundStyle(PoolDashboardTheme.textSecondary)
        }
    }

    private var coverageGapSummary: some View {
        Group {
            if let firstGap = timeline.gaps.first {
                PanelStatusCalloutView(
                    message: gapSummaryText(firstGap: firstGap, extraGapCount: timeline.gaps.count - 1),
                    title: L10n.text("schedule.gap.title"),
                    tone: .warning
                )
            } else {
                PanelStatusCalloutView(
                    message: L10n.text("schedule.gap.none"),
                    title: L10n.text("schedule.gap.title"),
                    tone: .success
                )
            }
        }
    }

    private func gapSummaryText(firstGap: GapRange, extraGapCount: Int) -> String {
        let base = L10n.text(
            "schedule.gap.first_format",
            localizedMonthDayHourMinuteText(firstGap.start),
            localizedMonthDayHourMinuteText(firstGap.end)
        )
        guard extraGapCount > 0 else { return base }
        return base + " " + L10n.text("schedule.gap.more_format", extraGapCount)
    }

    private var upcomingEvents: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("schedule.events.title"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PoolDashboardTheme.textPrimary)

            ForEach(Array(timeline.events.prefix(12).enumerated()), id: \.offset) { _, event in
                HStack(spacing: 8) {
                    Text(localizedMonthDayHourMinuteText(event.date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                        .monospacedDigit()
                        .frame(width: 128, alignment: .leading)

                    Text(event.accountName)
                        .font(.caption)
                        .foregroundStyle(PoolDashboardTheme.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(event.kind.title)
                        .statusBadge(tone: event.kind.badgeTone)
                }
            }

            if timeline.events.count > 12 {
                Text(L10n.text("schedule.events.more_format", timeline.events.count - 12))
                    .font(.caption)
                    .foregroundStyle(PoolDashboardTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .dashboardInfoCard()
    }

    private func coverageRowLabel(for row: CoverageRow) -> String {
        guard let first = row.slots.first, let last = row.slots.last else {
            return L10n.text("schedule.summary.not_available")
        }
        let dayText = first.start.formatted(.dateTime.locale(L10n.locale()).month().day())
        let startHour = first.start.formatted(.dateTime.locale(L10n.locale()).hour())
        let endHour = last.end.formatted(.dateTime.locale(L10n.locale()).hour())
        return L10n.text("schedule.row.range_format", dayText, startHour, endHour)
    }

    private func fillColor(for slot: CoverageSlot) -> Color {
        if slot.availableAccountCount == 0 {
            return noCoverageColor
        }
        if slot.resettingAccountCount > 0 {
            return partialCoverageColor
        }
        return fullCoverageColor
    }

    private var fullCoverageColor: Color {
        PoolDashboardTheme.glowA.opacity(PoolDashboardTheme.isLightPalette ? 0.42 : 0.62)
    }

    private var partialCoverageColor: Color {
        PoolDashboardTheme.warning.opacity(PoolDashboardTheme.isLightPalette ? 0.40 : 0.65)
    }

    private var noCoverageColor: Color {
        PoolDashboardTheme.danger.opacity(PoolDashboardTheme.isLightPalette ? 0.50 : 0.75)
    }

    private func buildEvents(from start: Date, to end: Date) -> [ResetEvent] {
        let range = start...end
        var events: [ResetEvent] = []

        for account in accounts {
            let normalizedName = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let accountName = normalizedName.isEmpty ? L10n.text("account.unknown") : normalizedName

            if let weeklyReset = account.usageWindowResetAt {
                for occurrence in repeatingOccurrences(
                    reference: weeklyReset,
                    interval: 7 * 24 * 3_600,
                    within: range
                ) {
                    events.append(
                        ResetEvent(
                            accountID: account.id,
                            accountName: accountName,
                            date: occurrence,
                            kind: .weekly
                        )
                    )
                }
            }

            if account.isPaid, let fiveHourReset = account.primaryUsageResetAt {
                for occurrence in repeatingOccurrences(
                    reference: fiveHourReset,
                    interval: 5 * 3_600,
                    within: range
                ) {
                    events.append(
                        ResetEvent(
                            accountID: account.id,
                            accountName: accountName,
                            date: occurrence,
                            kind: .fiveHour
                        )
                    )
                }
            }
        }

        return events.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.accountID.uuidString < rhs.accountID.uuidString
            }
            return lhs.date < rhs.date
        }
    }

    private func repeatingOccurrences(
        reference: Date,
        interval: TimeInterval,
        within range: ClosedRange<Date>,
        maxCount: Int = 720
    ) -> [Date] {
        guard interval > 0 else { return [] }

        let delta = range.lowerBound.timeIntervalSince(reference)
        let stepCount = Int(ceil(delta / interval))
        var current = reference.addingTimeInterval(Double(stepCount) * interval)
        while current < range.lowerBound {
            current = current.addingTimeInterval(interval)
        }

        var occurrences: [Date] = []
        while current <= range.upperBound, occurrences.count < maxCount {
            occurrences.append(current)
            current = current.addingTimeInterval(interval)
        }

        return occurrences
    }

    private func buildSlots(
        from start: Date,
        hours: Int,
        events: [ResetEvent],
        trackedAccountCount: Int
    ) -> [CoverageSlot] {
        let hourInterval: TimeInterval = 3_600
        var slots: [CoverageSlot] = []
        var eventIndex = 0

        for hour in 0..<hours {
            let slotStart = start.addingTimeInterval(Double(hour) * hourInterval)
            let slotEnd = slotStart.addingTimeInterval(hourInterval)

            while eventIndex < events.count, events[eventIndex].date < slotStart {
                eventIndex += 1
            }

            var index = eventIndex
            var slotEvents: [ResetEvent] = []
            while index < events.count, events[index].date < slotEnd {
                slotEvents.append(events[index])
                index += 1
            }

            eventIndex = index
            slots.append(
                CoverageSlot(
                    start: slotStart,
                    end: slotEnd,
                    events: slotEvents,
                    trackedAccountCount: trackedAccountCount,
                    resettingAccountIDs: Set(slotEvents.map(\.accountID))
                )
            )
        }

        return slots
    }

    private func buildGapRanges(from slots: [CoverageSlot]) -> [GapRange] {
        var gaps: [GapRange] = []
        var activeGapStart: Date?

        for slot in slots {
            if !slot.hasCoverage {
                if activeGapStart == nil {
                    activeGapStart = slot.start
                }
            } else if let gapStart = activeGapStart {
                gaps.append(GapRange(start: gapStart, end: slot.start))
                activeGapStart = nil
            }
        }

        if let gapStart = activeGapStart, let finalSlot = slots.last {
            gaps.append(GapRange(start: gapStart, end: finalSlot.end))
        }

        return gaps
    }

    private func localizedMonthDayHourMinuteText(_ date: Date) -> String {
        date.formatted(.dateTime.locale(L10n.locale()).month().day().hour().minute())
    }
}

private struct DailyUsagePlanningWorkspacePanelView: View {
    private enum Weekday: String, CaseIterable, Identifiable {
        case mon
        case tue
        case wed
        case thu
        case fri
        case sat
        case sun

        var id: String { rawValue }

        var localizedTitle: String {
            L10n.text("schedule.plan.weekday.\(rawValue)")
        }
    }

    private struct NotificationRequest: Equatable {
        let key: String
        let title: String
        let body: String
        let markedNotifiedDays: [String: String]
        let alertLevel: DailyUsagePlanEvaluator.AlertLevel
    }

    @AppStorage("pool_dashboard.schedule.daily_plan_enabled")
    private var dailyPlanEnabled = true
    @AppStorage("pool_dashboard.schedule.daily_plan_notify_enabled")
    private var dailyPlanNotifyEnabled = true
    @AppStorage("pool_dashboard.schedule.daily_plan_warning_threshold_percent")
    private var dailyPlanWarningThresholdPercent = 80
    @AppStorage("pool_dashboard.schedule.weekly_account_limits")
    private var weeklyAccountLimitsRaw = ""
    @AppStorage("pool_dashboard.schedule.selected_weekday")
    private var selectedWeekdayRaw = DailyUsagePlanEvaluator.weekdayKey(for: Date())
    @AppStorage("pool_dashboard.schedule.daily_plan_notified_days")
    private var dailyPlanNotifiedDaysRaw = ""

    let accounts: [AgentAccount]
    let analyticsState: UsageAnalyticsState

    private var selectedWeekday: Weekday {
        Weekday(rawValue: selectedWeekdayRaw) ?? todayWeekday
    }

    private var todayWeekday: Weekday {
        Weekday(rawValue: DailyUsagePlanEvaluator.weekdayKey(for: Date())) ?? .mon
    }

    private var selectedDayBudgets: [String: Int] {
        DailyUsagePlanEvaluator.activeBudgets(
            for: weeklyBudgetMap[selectedWeekday.rawValue] ?? [:],
            availableAccountKeys: availableAccountKeys
        )
    }

    private var todayBudgets: [String: Int] {
        DailyUsagePlanEvaluator.activeBudgets(
            for: weeklyBudgetMap[todayWeekday.rawValue] ?? [:],
            availableAccountKeys: availableAccountKeys
        )
    }

    private var selectedDayPlannedPercent: Int {
        DailyUsagePlanEvaluator.plannedTotalPercent(for: selectedDayBudgets)
    }

    private var todayPlannedPercent: Int {
        DailyUsagePlanEvaluator.plannedTotalPercent(for: todayBudgets)
    }

    private var todayUsedPercent: Int {
        todayBudgets.keys.reduce(0) { partial, accountKey in
            partial + UsageAnalyticsEngine.summary(
                for: analyticsState,
                now: Date(),
                accountKey: accountKey
            ).todayWeeklyPercent
        }
    }

    private var plannedLimitForEvaluation: Int {
        max(1, todayPlannedPercent)
    }

    private var warningThresholdPercent: Int {
        DailyUsagePlanEvaluator.warningThresholdPercent(from: dailyPlanWarningThresholdPercent)
    }

    private var warningTriggerPercent: Int {
        DailyUsagePlanEvaluator.warningTriggerPercent(
            plannedLimitPercent: plannedLimitForEvaluation,
            warningThresholdPercent: warningThresholdPercent
        )
    }

    private var alertLevel: DailyUsagePlanEvaluator.AlertLevel {
        guard todayPlannedPercent > 0 else { return .none }
        return DailyUsagePlanEvaluator.alertLevel(
            todayUsedPercent: todayUsedPercent,
            plannedLimitPercent: plannedLimitForEvaluation,
            warningThresholdPercent: warningThresholdPercent
        )
    }

    private var remainingBudgetPercent: Int {
        guard todayPlannedPercent > 0 else { return 0 }
        return DailyUsagePlanEvaluator.remainingBudgetPercent(
            todayUsedPercent: todayUsedPercent,
            plannedLimitPercent: plannedLimitForEvaluation
        )
    }

    private var exceededByPercent: Int {
        guard todayPlannedPercent > 0 else { return 0 }
        return DailyUsagePlanEvaluator.exceededByPercent(
            todayUsedPercent: todayUsedPercent,
            plannedLimitPercent: plannedLimitForEvaluation
        )
    }

    private var progressRatio: Double {
        guard todayPlannedPercent > 0 else { return 0 }
        return DailyUsagePlanEvaluator.progressRatio(
            todayUsedPercent: todayUsedPercent,
            plannedLimitPercent: plannedLimitForEvaluation
        )
    }

    private var progressColor: Color {
        switch alertLevel {
        case .exceeded:
            return PoolDashboardTheme.danger
        case .warning:
            return PoolDashboardTheme.warning
        case .none:
            return PoolDashboardTheme.glowA
        }
    }

    private var deduplicatedAccounts: [AgentAccount] {
        var mapping: [String: AgentAccount] = [:]
        for account in accounts where mapping[account.deduplicationKey] == nil {
            mapping[account.deduplicationKey] = account
        }

        return mapping.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var availableAccountKeys: Set<String> {
        Set(deduplicatedAccounts.map(\.deduplicationKey))
    }

    private var weeklyBudgetMap: [String: [String: Int]] {
        guard let data = weeklyAccountLimitsRaw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private var notifiedDaysByScope: [String: String] {
        guard let data = dailyPlanNotifiedDaysRaw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                headerRow
                controlRow
                weekdayTabs
                allocationPanel
                summaryCards
                progressCard
                planStatusCallout
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
        .onAppear {
            normalizeSelectedWeekdayIfNeeded()
            evaluateDailyPlanNotificationIfNeeded()
        }
        .onChange(of: accountsSignature) { _, _ in
            evaluateDailyPlanNotificationIfNeeded()
        }
        .onChange(of: usageAnalyticsUpdatedAt) { _, _ in
            evaluateDailyPlanNotificationIfNeeded()
        }
        .onChange(of: dailyPlanEnabled) { _, _ in
            evaluateDailyPlanNotificationIfNeeded()
        }
        .onChange(of: dailyPlanNotifyEnabled) { _, _ in
            evaluateDailyPlanNotificationIfNeeded()
        }
        .onChange(of: dailyPlanWarningThresholdPercent) { _, _ in
            evaluateDailyPlanNotificationIfNeeded()
        }
        .onChange(of: weeklyAccountLimitsRaw) { _, _ in
            evaluateDailyPlanNotificationIfNeeded()
        }
    }

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("workspace.schedule.title"))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(PoolDashboardTheme.textPrimary.opacity(PoolDashboardTheme.groupLabelOpacity))

            Text(L10n.text("schedule.plan.weekly.subtitle"))
                .font(.footnote)
                .foregroundStyle(PoolDashboardTheme.textMuted)
        }
    }

    private var controlRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                planningToggles
                warningStepper
            }

            VStack(alignment: .leading, spacing: 10) {
                planningToggles
                warningStepper
            }
        }
        .dashboardInfoCard()
    }

    private var planningToggles: some View {
        HStack(spacing: 12) {
            Toggle(L10n.text("schedule.plan.toggle.enable"), isOn: $dailyPlanEnabled)
                .toggleStyle(.switch)

            Toggle(L10n.text("schedule.plan.toggle.notify"), isOn: $dailyPlanNotifyEnabled)
                .toggleStyle(.switch)
                .disabled(!dailyPlanEnabled)
        }
    }

    private var warningStepper: some View {
        Stepper(value: $dailyPlanWarningThresholdPercent, in: 1...99, step: 1) {
            Text(L10n.text("schedule.plan.limit.warning.format", warningThresholdPercent))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PoolDashboardTheme.textSecondary)
        }
        .disabled(!dailyPlanEnabled)
    }

    private var weekdayTabs: some View {
        Picker("", selection: $selectedWeekdayRaw) {
            ForEach(Weekday.allCases) { weekday in
                Text(weekday.localizedTitle).tag(weekday.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(!dailyPlanEnabled)
    }

    private var allocationPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("schedule.plan.allocations.title"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PoolDashboardTheme.textPrimary)
                    Text(L10n.text("schedule.plan.allocations.subtitle", selectedWeekday.localizedTitle))
                        .font(.caption)
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                }

                Spacer(minLength: 0)

                Button(L10n.text("schedule.plan.allocations.clear_day")) {
                    clearSelectedDayPlan()
                }
                .buttonStyle(.bordered)
                .disabled(!dailyPlanEnabled || selectedDayBudgets.isEmpty)
            }

            if deduplicatedAccounts.isEmpty {
                Text(L10n.text("schedule.plan.timeline.empty"))
                    .font(.caption)
                    .foregroundStyle(PoolDashboardTheme.textMuted)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 10, alignment: .top)
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(deduplicatedAccounts, id: \.deduplicationKey) { account in
                        allocationCard(for: account)
                    }
                }
            }
        }
        .dashboardInfoCard()
    }

    private func allocationCard(for account: AgentAccount) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            allocationAccountLabel(account)
            allocationStepper(for: account)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PoolDashboardTheme.panelMutedFill.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(PoolDashboardTheme.panelStroke.opacity(0.55), lineWidth: 1)
        )
    }

    private func allocationAccountLabel(_ account: AgentAccount) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(account.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PoolDashboardTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(account.isPaid ? L10n.text("account.paid_badge") : L10n.text("schedule.plan.account.free"))
                .font(.caption2.weight(.medium))
                .foregroundStyle(PoolDashboardTheme.textMuted)
        }
    }

    private func allocationStepper(for account: AgentAccount) -> some View {
        Stepper(value: weekdayBudgetBinding(for: account.deduplicationKey), in: 0...500, step: 5) {
            Text(L10n.text("schedule.plan.account_budget.format", budget(for: account.deduplicationKey)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(PoolDashboardTheme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .disabled(!dailyPlanEnabled)
    }

    private var summaryCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { summaryCardsContent }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                summaryCardsContent
            }
        }
    }

    private var summaryCardsContent: some View {
        Group {
            summaryCard(
                title: L10n.text("schedule.plan.summary.selected_day"),
                value: selectedWeekday.localizedTitle
            )
            summaryCard(
                title: L10n.text("schedule.plan.summary.selected_day_budget"),
                value: "\(selectedDayPlannedPercent)%"
            )
            summaryCard(
                title: L10n.text("schedule.plan.summary.today_used"),
                value: "\(todayUsedPercent)%"
            )
            summaryCard(
                title: L10n.text("schedule.plan.summary.today_budget"),
                value: todayPlannedPercent > 0 ? "\(todayPlannedPercent)%" : L10n.text("schedule.plan.unplanned")
            )
            summaryCard(
                title: L10n.text("schedule.plan.summary.assigned_accounts"),
                value: "\(DailyUsagePlanEvaluator.plannedAccountCount(for: selectedDayBudgets))"
            )
        }
    }

    private func summaryCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PoolDashboardTheme.textMuted)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PoolDashboardTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardInfoCard()
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text("schedule.plan.progress.title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textPrimary)

                Spacer(minLength: 0)

                if todayPlannedPercent <= 0 {
                    Text(L10n.text("schedule.plan.unplanned"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                } else if alertLevel == .exceeded {
                    Text(L10n.text("schedule.plan.progress.over", exceededByPercent))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PoolDashboardTheme.danger)
                } else if alertLevel == .warning {
                    Text(L10n.text("schedule.plan.progress.warning", warningThresholdPercent))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PoolDashboardTheme.warning)
                } else {
                    Text(L10n.text("schedule.plan.progress.within"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PoolDashboardTheme.success)
                }
            }

            Text(todayPlannedPercent > 0
                ? L10n.text("schedule.plan.progress.warning_trigger", warningTriggerPercent)
                : L10n.text("schedule.plan.progress.no_today_plan"))
                .font(.caption)
                .foregroundStyle(PoolDashboardTheme.textMuted)

            ProgressView(value: min(max(progressRatio, 0), 1))
                .tint(progressColor)

            if progressRatio > 1 {
                ProgressView(value: min(progressRatio / 2, 1))
                    .tint(PoolDashboardTheme.danger.opacity(0.75))
            }
        }
        .dashboardInfoCard()
    }

    private var planStatusCallout: some View {
        if todayPlannedPercent <= 0 {
            return PanelStatusCalloutView(
                message: L10n.text("schedule.plan.callout.unplanned.message", todayWeekday.localizedTitle),
                title: L10n.text("schedule.plan.callout.unplanned.title"),
                tone: .info
            )
        }

        switch alertLevel {
        case .exceeded:
            return PanelStatusCalloutView(
                message: L10n.text(
                    "schedule.plan.callout.exceeded.message",
                    todayUsedPercent,
                    exceededByPercent
                ),
                title: L10n.text("schedule.plan.callout.exceeded.title"),
                tone: .warning
            )
        case .warning:
            return PanelStatusCalloutView(
                message: L10n.text(
                    "schedule.plan.callout.warning.message",
                    todayUsedPercent,
                    warningTriggerPercent,
                    plannedLimitForEvaluation
                ),
                title: L10n.text("schedule.plan.callout.warning.title"),
                tone: .info
            )
        case .none:
            return PanelStatusCalloutView(
                message: L10n.text(
                    "schedule.plan.callout.on_track.message",
                    remainingBudgetPercent
                ),
                title: L10n.text("schedule.plan.callout.on_track.title"),
                tone: .success
            )
        }
    }

    private var usageAnalyticsUpdatedAt: TimeInterval {
        analyticsState.lastUpdatedAt?.timeIntervalSince1970 ?? 0
    }

    private var accountsSignature: String {
        deduplicatedAccounts
            .map { "\($0.deduplicationKey)|\($0.usedUnits)|\($0.quota)|\($0.primaryUsagePercent ?? -1)" }
            .joined(separator: "\n")
    }

    private func normalizeSelectedWeekdayIfNeeded() {
        if Weekday(rawValue: selectedWeekdayRaw) == nil {
            selectedWeekdayRaw = todayWeekday.rawValue
        }
    }

    private func budget(for accountKey: String) -> Int {
        max(0, selectedDayBudgets[accountKey] ?? 0)
    }

    private func weekdayBudgetBinding(for accountKey: String) -> Binding<Int> {
        Binding(
            get: {
                budget(for: accountKey)
            },
            set: { newValue in
                var updated = weeklyBudgetMap
                var dayBudgets = updated[selectedWeekday.rawValue] ?? [:]
                let clamped = max(0, newValue)
                if clamped == 0 {
                    dayBudgets.removeValue(forKey: accountKey)
                } else {
                    dayBudgets[accountKey] = clamped
                }
                updated[selectedWeekday.rawValue] = dayBudgets
                persistWeeklyBudgetMap(updated)
            }
        )
    }

    private func clearSelectedDayPlan() {
        var updated = weeklyBudgetMap
        updated[selectedWeekday.rawValue] = [:]
        persistWeeklyBudgetMap(updated)
    }

    private func evaluateDailyPlanNotificationIfNeeded() {
        guard let request = dailyPlanNotificationRequestIfNeeded() else {
            return
        }

        DesktopNotifier.requestAuthorizationIfNeeded()
        DesktopNotifier.post(
            key: request.key,
            title: request.title,
            body: request.body,
            minInterval: 0
        )

        persistNotifiedDays(request.markedNotifiedDays)
    }

    private func dailyPlanNotificationRequestIfNeeded(now: Date = Date()) -> NotificationRequest? {
        let todayKey = dayKey(now)
        let scopeKey = "weekday:\(todayWeekday.rawValue)"
        let notified = notifiedDaysByScope
        guard DailyUsagePlanEvaluator.shouldNotify(
            isPlanEnabled: dailyPlanEnabled && todayPlannedPercent > 0,
            isDesktopNotifyEnabled: dailyPlanNotifyEnabled,
            alertLevel: alertLevel,
            scopeStorageKey: scopeKey,
            todayKey: todayKey,
            notifiedDaysByScopeAndLevel: notified
        ) else {
            return nil
        }

        return NotificationRequest(
            key: "schedule.weekly-plan.\(scopeKey).\(alertLevel.rawValue).\(todayKey)",
            title: notificationTitle,
            body: notificationBody,
            markedNotifiedDays: DailyUsagePlanEvaluator.markNotified(
                alertLevel: alertLevel,
                scopeStorageKey: scopeKey,
                todayKey: todayKey,
                notifiedDaysByScopeAndLevel: notified
            ),
            alertLevel: alertLevel
        )
    }

    private var notificationTitle: String {
        switch alertLevel {
        case .warning:
            return L10n.text("schedule.plan.notification.warning.title")
        case .exceeded:
            return L10n.text("schedule.plan.notification.exceeded.title")
        case .none:
            return L10n.text("schedule.plan.notification.title")
        }
    }

    private var notificationBody: String {
        switch alertLevel {
        case .warning:
            return L10n.text(
                "schedule.plan.notification.warning.body",
                todayWeekday.localizedTitle,
                todayUsedPercent,
                warningTriggerPercent,
                plannedLimitForEvaluation
            )
        case .exceeded:
            return L10n.text(
                "schedule.plan.notification.exceeded.body",
                todayWeekday.localizedTitle,
                todayUsedPercent,
                plannedLimitForEvaluation,
                exceededByPercent
            )
        case .none:
            return L10n.text(
                "schedule.plan.notification.body",
                todayWeekday.localizedTitle,
                todayUsedPercent,
                plannedLimitForEvaluation,
                exceededByPercent
            )
        }
    }

    private func persistWeeklyBudgetMap(_ map: [String: [String: Int]]) {
        guard let data = try? JSONEncoder().encode(map),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return
        }
        weeklyAccountLimitsRaw = encoded
    }

    private func persistNotifiedDays(_ map: [String: String]) {
        guard let data = try? JSONEncoder().encode(map),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return
        }
        dailyPlanNotifiedDaysRaw = encoded
    }

    private func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct UsageAnalyticsWorkspacePanelView: View {
    private enum AnalysisBasis: String, CaseIterable, Identifiable {
        case usage
        case remaining
        case wasted
        case delay

        var id: String { rawValue }
    }

    private enum AccountSortMode: String, CaseIterable, Identifiable {
        case name
        case weeklyUsage
        case fiveHourUsage
        case weeklyRemaining
        case fiveHourRemaining

        var id: String { rawValue }
    }

    private enum ChartGranularity: String, CaseIterable, Identifiable {
        case daily
        case weekly

        var id: String { rawValue }
    }

    private struct ChartEntry: Identifiable {
        let id: String
        let label: String
        let value: Int
    }

    private struct AccountAnalyticsMetrics {
        let name: String
        let isPaid: Bool
        let weeklyUsage: Int
        let fiveHourUsage: Int
        let weeklyRemaining: Int
        let fiveHourRemaining: Int
    }

    let analyticsState: UsageAnalyticsState
    let accounts: [AgentAccount]
    let onClearIdleDelay: (_ accountKey: String?) -> Void
    @State private var analysisBasis: AnalysisBasis = .usage
    @State private var chartGranularity: ChartGranularity = .daily
    @State private var accountSortMode: AccountSortMode = .name
    @State private var selectedAccountKey: String? = nil
    @State private var exportStatus: (message: String, tone: PanelStatusCalloutView.Tone)? = nil

    private var summary: UsageAnalyticsSummary {
        UsageAnalyticsEngine.summary(
            for: analyticsState,
            now: Date(),
            accountKey: selectedAccountKey
        )
    }

    private var dailyTotals: [UsageAnalyticsDailyTotal] {
        UsageAnalyticsEngine.dailyTotals(
            for: analyticsState,
            now: Date(),
            days: 7,
            accountKey: selectedAccountKey
        )
    }

    private var weeklyTotals: [UsageAnalyticsWeeklyTotal] {
        UsageAnalyticsEngine.weeklyTotals(
            for: analyticsState,
            now: Date(),
            weeks: 8,
            accountKey: selectedAccountKey
        )
    }

    private var etasByAccountKey: [String: UsageAnalyticsETA] {
        UsageAnalyticsEngine.etas(
            accounts: accounts,
            state: analyticsState,
            now: Date()
        )
    }

    private var sortedETAs: [UsageAnalyticsETA] {
        etasByAccountKey
            .values
            .sorted { lhs, rhs in
                if lhs.remainingPercent != rhs.remainingPercent {
                    return lhs.remainingPercent > rhs.remainingPercent
                }
                return lhs.accountKey.localizedCaseInsensitiveCompare(rhs.accountKey) == .orderedAscending
            }
    }

    private var thresholdEvents: [UsageAnalyticsThresholdEvent] {
        UsageAnalyticsEngine.thresholdTimeline(
            for: analyticsState,
            accountKey: selectedAccountKey,
            limit: 8
        )
    }

    private var switchEffectiveness: UsageAnalyticsSwitchEffectiveness {
        UsageAnalyticsEngine.switchEffectiveness(for: analyticsState)
    }

    private var coverageSummary: UsageAnalyticsCoverageSummary {
        UsageAnalyticsEngine.projectedCoverage(accounts: accounts, now: Date())
    }

    private var anomalyEvents: [UsageAnalyticsAnomaly] {
        UsageAnalyticsEngine.anomalies(
            state: analyticsState,
            accounts: accounts,
            now: Date()
        )
    }

    private var recommendation: UsageAnalyticsRecommendation {
        UsageAnalyticsEngine.recommendation(
            accounts: accounts,
            activeAccountKey: analyticsState.lastActiveAccountKey,
            etasByAccountKey: etasByAccountKey
        )
    }

    private var accountNameByKey: [String: String] {
        var mapping: [String: String] = [:]
        for account in accounts {
            let key = account.usageAnalyticsAccountKey
            if mapping[key] == nil {
                mapping[key] = account.name
            }
        }
        return mapping
    }

    private func accountPickerTitle(for key: String) -> String {
        let name = accountNameByKey[key] ?? key
        guard deduplicatedAccountsByKey[key]?.isPaid == true else {
            return name
        }
        return "👑 \(name)"
    }

    private var selectableAccountKeys: [String] {
        let names = accountNameByKey
        let keys = Set(analyticsState.records.map(\.accountKey))
            .union(names.keys)
            .filter { shouldShowAccountKeyInPicker($0, names: names) }
        let accountsByKey = deduplicatedAccountsByKey
        let snapshotsByKey = latestSnapshotByKey
        let recordsByKey = latestRecordByKey
        let metricsByKey = Dictionary(uniqueKeysWithValues: keys.map { key in
            (
                key,
                accountMetrics(
                    for: key,
                    names: names,
                    accountsByKey: accountsByKey,
                    snapshotsByKey: snapshotsByKey,
                    recordsByKey: recordsByKey
                )
            )
        })
        return keys.sorted { lhs, rhs in
            accountKeySortComparator(lhs, rhs, metricsByKey: metricsByKey)
        }
    }

    private func shouldShowAccountKeyInPicker(_ key: String, names: [String: String]) -> Bool {
        if names[key] != nil {
            return true
        }

        // Older analytics snapshots may contain internal identity keys. Keep them in history,
        // but do not expose raw implementation details in the account picker.
        return !isInternalAnalyticsAccountKey(key)
    }

    private func isInternalAnalyticsAccountKey(_ key: String) -> Bool {
        key.hasPrefix("account:") || key.contains("|scope:")
    }

    private var latestSnapshotByKey: [String: UsageAnalyticsAccountSnapshot] {
        analyticsState.snapshots.reduce(into: [String: UsageAnalyticsAccountSnapshot]()) { result, snapshot in
            guard let existing = result[snapshot.accountKey] else {
                result[snapshot.accountKey] = snapshot
                return
            }
            if snapshot.lastSeenAt > existing.lastSeenAt {
                result[snapshot.accountKey] = snapshot
            }
        }
    }

    private var latestRecordByKey: [String: UsageAnalyticsRecord] {
        analyticsState.records.reduce(into: [String: UsageAnalyticsRecord]()) { result, record in
            guard let existing = result[record.accountKey] else {
                result[record.accountKey] = record
                return
            }
            if record.timestamp > existing.timestamp {
                result[record.accountKey] = record
            }
        }
    }

    private func accountMetrics(for key: String) -> AccountAnalyticsMetrics {
        accountMetrics(
            for: key,
            names: accountNameByKey,
            accountsByKey: deduplicatedAccountsByKey,
            snapshotsByKey: latestSnapshotByKey,
            recordsByKey: latestRecordByKey
        )
    }

    private func accountMetrics(
        for key: String,
        names: [String: String],
        accountsByKey: [String: AgentAccount],
        snapshotsByKey: [String: UsageAnalyticsAccountSnapshot],
        recordsByKey: [String: UsageAnalyticsRecord]
    ) -> AccountAnalyticsMetrics {
        let name = names[key] ?? key

        if let account = accountsByKey[key] {
            let weeklyUsage = account.secondaryUsagePercent ?? max(0, min(100, Int((account.usageRatio * 100).rounded())))
            let fiveHourUsage = account.primaryUsagePercent ?? -1
            let weeklyRemaining = max(0, min(100, Int((account.remainingRatio * 100).rounded())))
            let fiveHourRemaining = account.primaryUsagePercent.map { max(0, 100 - min(max($0, 0), 100)) } ?? -1
            return AccountAnalyticsMetrics(
                name: name,
                isPaid: account.isPaid,
                weeklyUsage: weeklyUsage,
                fiveHourUsage: fiveHourUsage,
                weeklyRemaining: weeklyRemaining,
                fiveHourRemaining: fiveHourRemaining
            )
        }

        if let snapshot = snapshotsByKey[key] {
            let weeklyUsage = max(0, min(100, snapshot.lastWeeklyPercent))
            let fiveHourUsage = snapshot.lastFiveHourPercent.map { max(0, min(100, $0)) } ?? -1
            let weeklyRemaining = max(0, 100 - weeklyUsage)
            let fiveHourRemaining = fiveHourUsage >= 0 ? max(0, 100 - fiveHourUsage) : -1
            return AccountAnalyticsMetrics(
                name: name,
                isPaid: false,
                weeklyUsage: weeklyUsage,
                fiveHourUsage: fiveHourUsage,
                weeklyRemaining: weeklyRemaining,
                fiveHourRemaining: fiveHourRemaining
            )
        }

        if let record = recordsByKey[key] {
            let weeklyUsage = max(0, min(100, record.weeklyAbsolutePercent))
            let fiveHourUsage = record.fiveHourAbsolutePercent.map { max(0, min(100, $0)) } ?? -1
            let weeklyRemaining = max(0, min(100, record.weeklyRemainingPercent))
            let fiveHourRemaining = record.fiveHourRemainingPercent.map { max(0, min(100, $0)) } ?? -1
            return AccountAnalyticsMetrics(
                name: name,
                isPaid: false,
                weeklyUsage: weeklyUsage,
                fiveHourUsage: fiveHourUsage,
                weeklyRemaining: weeklyRemaining,
                fiveHourRemaining: fiveHourRemaining
            )
        }

        return AccountAnalyticsMetrics(
            name: name,
            isPaid: false,
            weeklyUsage: 0,
            fiveHourUsage: -1,
            weeklyRemaining: 0,
            fiveHourRemaining: -1
        )
    }

    private func accountKeySortComparator(_ lhs: String, _ rhs: String) -> Bool {
        let metricsByKey = [
            lhs: accountMetrics(for: lhs),
            rhs: accountMetrics(for: rhs)
        ]
        return accountKeySortComparator(lhs, rhs, metricsByKey: metricsByKey)
    }

    private func accountKeySortComparator(
        _ lhs: String,
        _ rhs: String,
        metricsByKey: [String: AccountAnalyticsMetrics]
    ) -> Bool {
        guard let left = metricsByKey[lhs], let right = metricsByKey[rhs] else {
            return lhs < rhs
        }

        if left.isPaid != right.isPaid {
            return left.isPaid && !right.isPaid
        }

        func compareDescending(_ leftValue: Int, _ rightValue: Int) -> Bool? {
            if leftValue != rightValue {
                return leftValue > rightValue
            }
            return nil
        }

        let primaryDecision: Bool? = {
            switch accountSortMode {
            case .name:
                return nil
            case .weeklyUsage:
                return compareDescending(left.weeklyUsage, right.weeklyUsage)
            case .fiveHourUsage:
                return compareDescending(left.fiveHourUsage, right.fiveHourUsage)
            case .weeklyRemaining:
                return compareDescending(left.weeklyRemaining, right.weeklyRemaining)
            case .fiveHourRemaining:
                return compareDescending(left.fiveHourRemaining, right.fiveHourRemaining)
            }
        }()

        if let primaryDecision {
            return primaryDecision
        }

        let nameComparison = left.name.localizedCaseInsensitiveCompare(right.name)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }
        return lhs < rhs
    }

    private var chartEntries: [ChartEntry] {
        switch chartGranularity {
        case .daily:
            let values: [UsageAnalyticsDailyTotal]
            switch analysisBasis {
            case .usage:
                values = dailyTotals
            case .remaining:
                values = dailyRemainingTotals
            case .wasted:
                values = dailyWastedTotals
            case .delay:
                values = dailyIdleDelayTotals
            }
            return values.map { daily in
                ChartEntry(
                    id: "daily-\(analysisBasis.rawValue)-\(Int(daily.date.timeIntervalSince1970))",
                    label: daily.date.formatted(.dateTime.locale(L10n.locale()).weekday(.abbreviated)),
                    value: daily.totalWeeklyPercent
                )
            }
        case .weekly:
            let values: [UsageAnalyticsWeeklyTotal]
            switch analysisBasis {
            case .usage:
                values = weeklyTotals
            case .remaining:
                values = weeklyRemainingTotals
            case .wasted:
                values = weeklyWastedTotals
            case .delay:
                values = weeklyIdleDelayTotals
            }
            return values.map { weekly in
                ChartEntry(
                    id: "weekly-\(analysisBasis.rawValue)-\(Int(weekly.weekStartDate.timeIntervalSince1970))",
                    label: weeklyLabel(weekly.weekStartDate),
                    value: weekly.totalWeeklyPercent
                )
            }
        }
    }

    private var deduplicatedAccountsByKey: [String: AgentAccount] {
        var mapping: [String: AgentAccount] = [:]
        for account in accounts {
            if mapping[account.usageAnalyticsAccountKey] == nil {
                mapping[account.usageAnalyticsAccountKey] = account
            }
        }
        return mapping
    }

    private var filteredDeduplicatedAccounts: [AgentAccount] {
        if let selectedAccountKey,
           let selected = deduplicatedAccountsByKey[selectedAccountKey] {
            return [selected]
        }
        return Array(deduplicatedAccountsByKey.values)
    }

    private var averageWeeklyRemainingPercent: Int {
        let deduplicated = filteredDeduplicatedAccounts
        guard !deduplicated.isEmpty else { return 0 }
        let sum = deduplicated.reduce(0) { partial, account in
            partial + max(0, min(100, Int((account.remainingRatio * 100).rounded())))
        }
        return Int((Double(sum) / Double(deduplicated.count)).rounded())
    }

    private var lowestWeeklyRemainingPercent: Int {
        let deduplicated = filteredDeduplicatedAccounts
        guard !deduplicated.isEmpty else { return 0 }
        return deduplicated
            .map { max(0, min(100, Int(($0.remainingRatio * 100).rounded()))) }
            .min() ?? 0
    }

    private var averageFiveHourRemainingPercent: Int {
        let deduplicated = filteredDeduplicatedAccounts
        let values = deduplicated.compactMap { account -> Int? in
            guard let absolute = account.primaryUsagePercent else { return nil }
            return max(0, 100 - min(max(absolute, 0), 100))
        }
        guard !values.isEmpty else { return 0 }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    private var lowestFiveHourRemainingPercent: Int {
        let deduplicated = filteredDeduplicatedAccounts
        let values = deduplicated.compactMap { account -> Int? in
            guard let absolute = account.primaryUsagePercent else { return nil }
            return max(0, 100 - min(max(absolute, 0), 100))
        }
        return values.min() ?? 0
    }

    private var dailyRemainingTotals: [UsageAnalyticsDailyTotal] {
        dailyRemainingSeries(days: 7)
    }

    private var weeklyRemainingTotals: [UsageAnalyticsWeeklyTotal] {
        weeklyRemainingSeries(weeks: 8)
    }

    private var dailyWastedTotals: [UsageAnalyticsDailyTotal] {
        dailyWastedSeries(days: 7)
    }

    private var weeklyWastedTotals: [UsageAnalyticsWeeklyTotal] {
        weeklyWastedSeries(weeks: 8)
    }

    private var weeklyWastedResetEventCount: Int {
        let calendar = Calendar.autoupdatingCurrent
        let todayStart = calendar.startOfDay(for: Date())
        guard let periodStart = calendar.date(byAdding: .day, value: -6, to: todayStart),
              let periodEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            return 0
        }

        return analyticsState.records
            .filter {
                $0.timestamp >= periodStart
                && $0.timestamp < periodEnd
                && (selectedAccountKey == nil || $0.accountKey == selectedAccountKey)
            }
            .reduce(into: 0) { count, record in
                if record.weeklyWastedPercent > 0 {
                    count += 1
                }
            }
    }

    private var dailyIdleDelayTotals: [UsageAnalyticsDailyTotal] {
        dailyIdleDelaySeries(days: 7)
    }

    private var weeklyIdleDelayTotals: [UsageAnalyticsWeeklyTotal] {
        weeklyIdleDelaySeries(weeks: 8)
    }

    private var hasIdleDelayData: Bool {
        analyticsState.records.contains { record in
            (selectedAccountKey == nil || record.accountKey == selectedAccountKey)
            && record.weeklyIdleDelayMinutes > 0
        }
    }

    private var analysisBasisDescriptionText: String {
        switch analysisBasis {
        case .usage:
            return L10n.text("usage_analytics.basis.description.usage")
        case .remaining:
            return L10n.text("usage_analytics.basis.description.remaining")
        case .wasted:
            return L10n.text("usage_analytics.basis.description.wasted")
        case .delay:
            return L10n.text("usage_analytics.basis.description.delay")
        }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Text(L10n.text("usage_analytics.title"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(PoolDashboardTheme.textPrimary.opacity(PoolDashboardTheme.groupLabelOpacity))

                    Spacer(minLength: 0)

                    Text(lastUpdatedText)
                        .font(.caption)
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                }

                Text(L10n.text("usage_analytics.subtitle"))
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                HStack(alignment: .top, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(L10n.text("usage_analytics.basis.label"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PoolDashboardTheme.textMuted)

                        Picker(L10n.text("usage_analytics.basis.label"), selection: $analysisBasis) {
                            Text(L10n.text("usage_analytics.basis.usage")).tag(AnalysisBasis.usage)
                            Text(L10n.text("usage_analytics.basis.remaining")).tag(AnalysisBasis.remaining)
                            Text(L10n.text("usage_analytics.basis.wasted")).tag(AnalysisBasis.wasted)
                            Text(L10n.text("usage_analytics.basis.delay")).tag(AnalysisBasis.delay)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 460)
                    }

                    Text(analysisBasisDescriptionText)
                        .font(.caption)
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if analysisBasis == .usage {
                    HStack(spacing: 8) {
                        summaryCard(
                            title: L10n.text("usage_analytics.summary.today_weekly"),
                            value: L10n.text("usage_analytics.percent_format", summary.todayWeeklyPercent)
                        )
                        summaryCard(
                            title: L10n.text("usage_analytics.summary.weekly"),
                            value: L10n.text("usage_analytics.percent_format", summary.weekWeeklyPercent)
                        )
                        summaryCard(
                            title: L10n.text("usage_analytics.summary.today_five_hour"),
                            value: L10n.text("usage_analytics.percent_format", summary.todayFiveHourPercent)
                        )
                        summaryCard(
                            title: L10n.text("usage_analytics.summary.week_five_hour"),
                            value: L10n.text("usage_analytics.percent_format", summary.weekFiveHourPercent)
                        )
                    }
                } else if analysisBasis == .remaining {
                    HStack(spacing: 8) {
                        summaryCard(
                            title: L10n.text("usage_analytics.summary.avg_weekly_remaining"),
                            value: L10n.text("usage_analytics.percent_format", averageWeeklyRemainingPercent)
                        )
                        summaryCard(
                            title: L10n.text("usage_analytics.summary.lowest_weekly_remaining"),
                            value: L10n.text("usage_analytics.percent_format", lowestWeeklyRemainingPercent)
                        )
                        summaryCard(
                            title: L10n.text("usage_analytics.summary.avg_five_hour_remaining"),
                            value: L10n.text("usage_analytics.percent_format", averageFiveHourRemainingPercent)
                        )
                        summaryCard(
                            title: L10n.text("usage_analytics.summary.lowest_five_hour_remaining"),
                            value: L10n.text("usage_analytics.percent_format", lowestFiveHourRemainingPercent)
                        )
                    }
                } else if analysisBasis == .delay {
                    idleDelaySummaryView
                } else {
                    wastedUsageSummaryView
                }

                if analyticsState.records.isEmpty {
                    PanelStatusCalloutView(
                        message: L10n.text("usage_analytics.empty"),
                        title: L10n.text("usage_analytics.empty_title"),
                        tone: .warning
                    )
                } else {
                    chartView
                    insightsView
                    UsageAnalyticsStableDetailSectionsView(
                        analyticsState: analyticsState,
                        accounts: accounts,
                        selectedAccountKey: selectedAccountKey
                    )
                    .equatable()
                }
            }
        }
        .sectionCardStyle()
        .onChange(of: selectableAccountKeys) { _, keys in
            guard let selectedAccountKey else { return }
            if !keys.contains(selectedAccountKey) {
                self.selectedAccountKey = nil
            }
        }
    }

    private var wastedUsageSummaryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(L10n.text("usage_analytics.section.wasted"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                Spacer(minLength: 0)

                Text(L10n.text("usage_analytics.summary.wasted_events_format", weeklyWastedResetEventCount))
                    .font(.caption2)
                    .foregroundStyle(PoolDashboardTheme.textMuted)
            }

            HStack(spacing: 8) {
                summaryCard(
                    title: L10n.text("usage_analytics.summary.wasted_today_weekly"),
                    value: L10n.text("usage_analytics.percent_format", summary.todayWastedWeeklyPercent)
                )
                summaryCard(
                    title: L10n.text("usage_analytics.summary.wasted_weekly"),
                    value: L10n.text("usage_analytics.percent_format", summary.weekWastedWeeklyPercent)
                )
            }
        }
    }

    private var idleDelaySummaryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(L10n.text("usage_analytics.section.idle_delay"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                Spacer(minLength: 0)

                Button(L10n.text("usage_analytics.delay.clear")) {
                    onClearIdleDelay(selectedAccountKey)
                }
                .buttonStyle(.bordered)
                .disabled(!hasIdleDelayData)

                Text(L10n.text("usage_analytics.summary.delay_events_format", summary.weekIdleDelayEvents))
                    .font(.caption2)
                    .foregroundStyle(PoolDashboardTheme.textMuted)
            }

            HStack(spacing: 8) {
                summaryCard(
                    title: L10n.text("usage_analytics.summary.delay_today"),
                    value: L10n.text("usage_analytics.minutes_format", summary.todayIdleDelayMinutes)
                )
                summaryCard(
                    title: L10n.text("usage_analytics.summary.delay_week"),
                    value: L10n.text("usage_analytics.minutes_format", summary.weekIdleDelayMinutes)
                )
                summaryCard(
                    title: L10n.text("usage_analytics.summary.delay_avg_per_event"),
                    value: delayAveragePerEventText
                )
            }
        }
    }

    private var delayAveragePerEventText: String {
        guard summary.weekIdleDelayEvents > 0 else {
            return L10n.text("usage_analytics.minutes_format", 0)
        }
        let average = Int((Double(summary.weekIdleDelayMinutes) / Double(summary.weekIdleDelayEvents)).rounded())
        return L10n.text("usage_analytics.minutes_format", average)
    }

    private var lastUpdatedText: String {
        guard let lastUpdatedAt = analyticsState.lastUpdatedAt else {
            return L10n.text("usage_analytics.never_synced")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.locale()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastUpdatedAt, relativeTo: Date())
    }

    private var chartView: some View {
        let entries = chartEntries

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(
                    {
                        switch analysisBasis {
                        case .usage:
                            return L10n.text("usage_analytics.chart.title")
                        case .remaining:
                            return L10n.text("usage_analytics.chart.remaining_title")
                        case .wasted:
                            return L10n.text("usage_analytics.section.wasted")
                        case .delay:
                            return L10n.text("usage_analytics.section.idle_delay")
                        }
                    }()
                )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textPrimary)

                Spacer(minLength: 0)

                Picker(L10n.text("usage_analytics.chart.granularity"), selection: $chartGranularity) {
                    Text(L10n.text("usage_analytics.chart.daily"))
                        .tag(ChartGranularity.daily)
                    Text(L10n.text("usage_analytics.chart.weekly"))
                        .tag(ChartGranularity.weekly)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)

                Picker(L10n.text("usage_analytics.sort.label"), selection: $accountSortMode) {
                    Text(L10n.text("usage_analytics.sort.name"))
                        .tag(AccountSortMode.name)
                    Text(L10n.text("usage_analytics.sort.weekly_usage_desc"))
                        .tag(AccountSortMode.weeklyUsage)
                    Text(L10n.text("usage_analytics.sort.five_hour_usage_desc"))
                        .tag(AccountSortMode.fiveHourUsage)
                    Text(L10n.text("usage_analytics.sort.weekly_remaining_desc"))
                        .tag(AccountSortMode.weeklyRemaining)
                    Text(L10n.text("usage_analytics.sort.five_hour_remaining_desc"))
                        .tag(AccountSortMode.fiveHourRemaining)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 180)

                Picker(L10n.text("usage_analytics.chart.account"), selection: $selectedAccountKey) {
                    Text(L10n.text("usage_analytics.chart.all_accounts"))
                        .tag(Optional<String>.none)
                    ForEach(selectableAccountKeys, id: \.self) { key in
                        Text(accountPickerTitle(for: key))
                            .tag(Optional(key))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            }

            GeometryReader { geometry in
                let points = chartPoints(for: entries, in: geometry.size)

                ZStack {
                    // horizontal guides for easier trend reading
                    Path { path in
                        let guideValues: [CGFloat] = [0, 0.5, 1]
                        for value in guideValues {
                            let y = chartY(forNormalizedValue: value, in: geometry.size)
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                    }
                    .stroke(PoolDashboardTheme.panelInnerStroke.opacity(0.25), style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))

                    if points.count > 1 {
                        curveAreaPath(points: points, in: geometry.size)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        PoolDashboardTheme.glowA.opacity(0.28),
                                        PoolDashboardTheme.glowA.opacity(0.03)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }

                    if points.count > 1 {
                        smoothCurvePath(points: points)
                            .stroke(
                                PoolDashboardTheme.glowA,
                                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                            )
                    }

                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        Circle()
                            .fill(PoolDashboardTheme.glowA)
                            .frame(width: 7, height: 7)
                            .position(point)
                    }
                }
            }
            .frame(height: 120)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(entries) { entry in
                    VStack(spacing: 4) {
                        Text(entry.label)
                            .font(.caption2)
                            .foregroundStyle(PoolDashboardTheme.textMuted)

                        Text(chartValueLabel(for: entry.value))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(PoolDashboardTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .dashboardInfoCard()
    }

    private func chartValueLabel(for value: Int) -> String {
        switch analysisBasis {
        case .delay:
            return L10n.text("usage_analytics.minutes_format", value)
        case .usage, .remaining, .wasted:
            return L10n.text("usage_analytics.percent_format", value)
        }
    }

    private func chartPoints(for entries: [ChartEntry], in size: CGSize) -> [CGPoint] {
        guard !entries.isEmpty else { return [] }

        let topPadding: CGFloat = 8
        let bottomPadding: CGFloat = 12
        let maxValue = max(entries.map(\.value).max() ?? 0, 1)
        let stepX = entries.count > 1 ? size.width / CGFloat(entries.count - 1) : 0
        let availableHeight = max(1, size.height - topPadding - bottomPadding)

        return entries.enumerated().map { index, entry in
            let ratio = CGFloat(max(0, entry.value)) / CGFloat(maxValue)
            let x = CGFloat(index) * stepX
            let y = topPadding + (1 - ratio) * availableHeight
            return CGPoint(x: x, y: y)
        }
    }

    private func weeklyLabel(_ weekStart: Date) -> String {
        weekStart.formatted(.dateTime.locale(L10n.locale()).month().day())
    }

    private func chartY(forNormalizedValue normalized: CGFloat, in size: CGSize) -> CGFloat {
        let topPadding: CGFloat = 8
        let bottomPadding: CGFloat = 12
        let clamped = min(max(normalized, 0), 1)
        let availableHeight = max(1, size.height - topPadding - bottomPadding)
        return topPadding + (1 - clamped) * availableHeight
    }

    private func smoothCurvePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }

        path.move(to: first)
        if points.count == 2, let second = points.last {
            path.addLine(to: second)
            return path
        }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)

            if index == 1 {
                path.addQuadCurve(to: midpoint, control: previous)
            } else {
                let beforePrevious = points[index - 2]
                let control = CGPoint(
                    x: previous.x,
                    y: previous.y + (current.y - beforePrevious.y) / 6
                )
                path.addQuadCurve(to: midpoint, control: control)
            }

            if index == points.count - 1 {
                path.addQuadCurve(to: current, control: current)
            }
        }

        return path
    }

    private func curveAreaPath(points: [CGPoint], in size: CGSize) -> Path {
        var path = smoothCurvePath(points: points)
        guard let first = points.first, let last = points.last else {
            return path
        }

        let baseY = size.height - 4
        path.addLine(to: CGPoint(x: last.x, y: baseY))
        path.addLine(to: CGPoint(x: first.x, y: baseY))
        path.closeSubpath()
        return path
    }

    private var insightsView: some View {
        HStack(spacing: 8) {
            if analysisBasis == .remaining {
                summaryCard(
                    title: L10n.text("usage_analytics.insight.lowest_remaining_account"),
                    value: lowestRemainingAccountText
                )
                summaryCard(
                    title: L10n.text("usage_analytics.insight.best_remaining_account"),
                    value: bestRemainingAccountText
                )
                summaryCard(
                    title: L10n.text("usage_analytics.insight.tracked_accounts"),
                    value: "\(deduplicatedAccountsByKey.count)"
                )
            } else {
                summaryCard(
                    title: L10n.text("usage_analytics.insight.peak_hour"),
                    value: peakHourText(summary.peakHour)
                )
                summaryCard(
                    title: L10n.text("usage_analytics.insight.peak_day"),
                    value: peakWeekdayText(summary.peakWeekday)
                )
                summaryCard(
                    title: L10n.text("usage_analytics.insight.top_account"),
                    value: topAccountText(key: summary.topAccountKey, weeklyPercent: summary.topAccountWeeklyPercent)
                )
            }
        }
    }

    private var operationsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L10n.text("usage_analytics.section.export"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textPrimary)

                Spacer(minLength: 0)

                Button(L10n.text("usage_analytics.export.copy_json")) {
                    copyJSONReportToClipboard()
                }
                .buttonStyle(.bordered)

                Button(L10n.text("usage_analytics.export.csv")) {
                    exportCSVReport()
                }
                .buttonStyle(.bordered)

                Button(L10n.text("usage_analytics.export.json")) {
                    exportJSONReport()
                }
                .buttonStyle(.bordered)
            }

            if let exportStatus {
                PanelStatusCalloutView(
                    message: exportStatus.message,
                    tone: exportStatus.tone
                )
            }
        }
        .dashboardInfoCard()
    }

    private var coverageAndSwitchView: some View {
        HStack(spacing: 8) {
            summaryCard(
                title: L10n.text("usage_analytics.summary.coverage"),
                value: ratioText(coverageSummary.coveredRatio)
            )
            summaryCard(
                title: L10n.text("usage_analytics.summary.uncovered_slots"),
                value: "\(coverageSummary.uncoveredSlots)/\(coverageSummary.totalSlots)"
            )
            summaryCard(
                title: L10n.text("usage_analytics.summary.switch_gain"),
                value: String(format: "%.1f%%", switchEffectiveness.averageRemainingGain)
            )
            summaryCard(
                title: L10n.text("usage_analytics.summary.switch_improved"),
                value: ratioText(switchEffectiveness.improvedRate)
            )
        }
    }

    private var recommendationView: some View {
        let targetName = recommendation.targetAccountKey.flatMap { accountNameByKey[$0] ?? $0 }
        let titleKey = targetName == nil ? "usage_analytics.recommendation.none" : "usage_analytics.recommendation.title"
        let message = targetName.map { "\($0) · \(recommendation.reason)" } ?? recommendation.reason
        return PanelStatusCalloutView(
            message: message,
            title: L10n.text(titleKey),
            tone: recommendation.targetAccountKey == nil ? .info : .success
        )
    }

    private var thresholdAndAnomalyView: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("usage_analytics.section.thresholds"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textPrimary)

                if thresholdEvents.isEmpty {
                    Text(L10n.text("usage_analytics.empty_thresholds"))
                        .font(.footnote)
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                } else {
                    ForEach(thresholdEvents) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(thresholdEventHeadline(event))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(PoolDashboardTheme.textSecondary)
                            Text(thresholdEventDetail(event))
                                .font(.caption)
                                .foregroundStyle(PoolDashboardTheme.textMuted)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dashboardInfoCard()

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("usage_analytics.section.anomalies"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textPrimary)

                if anomalyEvents.isEmpty {
                    Text(L10n.text("usage_analytics.empty_anomalies"))
                        .font(.footnote)
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                } else {
                    ForEach(anomalyEvents.prefix(6)) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(anomalyColor(for: event.severity))
                            Text(event.detail)
                                .font(.caption)
                                .foregroundStyle(PoolDashboardTheme.textMuted)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dashboardInfoCard()
        }
    }

    private var etaView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("usage_analytics.section.eta"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PoolDashboardTheme.textPrimary)

            if sortedETAs.isEmpty {
                Text(L10n.text("usage_analytics.empty_eta"))
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)
            } else {
                ForEach(displayedETAs, id: \.accountKey) { eta in
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(accountNameByKey[eta.accountKey] ?? eta.accountKey)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(PoolDashboardTheme.textSecondary)
                                .lineLimit(1)
                            Text(etaSubtitle(eta))
                                .font(.caption)
                                .foregroundStyle(PoolDashboardTheme.textMuted)
                        }

                        Spacer(minLength: 0)

                        Text(etaValueText(eta))
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(PoolDashboardTheme.textPrimary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .dashboardInfoCard()
    }

    private var displayedETAs: [UsageAnalyticsETA] {
        if let selectedAccountKey {
            return sortedETAs.filter { $0.accountKey == selectedAccountKey }
        }
        return Array(sortedETAs.prefix(6))
    }

    private func summaryCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PoolDashboardTheme.textMuted)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PoolDashboardTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardInfoCard()
    }

    private func peakHourText(_ hour: Int?) -> String {
        guard let hour else { return L10n.text("usage_analytics.not_available") }
        let calendar = Calendar.autoupdatingCurrent
        if let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) {
            return date.formatted(.dateTime.locale(L10n.locale()).hour(.defaultDigits(amPM: .abbreviated)))
        }
        return L10n.text("usage_analytics.not_available")
    }

    private func peakWeekdayText(_ weekday: Int?) -> String {
        guard let weekday else { return L10n.text("usage_analytics.not_available") }
        let formatter = DateFormatter()
        formatter.locale = L10n.locale()
        let symbols = formatter.weekdaySymbols ?? []
        guard weekday >= 1, weekday <= symbols.count else {
            return L10n.text("usage_analytics.not_available")
        }
        return symbols[weekday - 1]
    }

    private func topAccountText(key: String?, weeklyPercent: Int) -> String {
        guard let key else { return L10n.text("usage_analytics.not_available") }
        let name = accounts.first(where: { $0.usageAnalyticsAccountKey == key })?.name ?? key
        return L10n.text("usage_analytics.top_account_format", name, weeklyPercent)
    }

    private func thresholdEventHeadline(_ event: UsageAnalyticsThresholdEvent) -> String {
        let kind = event.kind == .weekly
            ? L10n.text("usage_analytics.threshold.weekly")
            : L10n.text("usage_analytics.threshold.five_hour")
        let account = accountNameByKey[event.accountKey] ?? event.accountKey
        return L10n.text("usage_analytics.threshold.headline", account, kind, event.thresholdPercent)
    }

    private func thresholdEventDetail(_ event: UsageAnalyticsThresholdEvent) -> String {
        let previous = L10n.text("usage_analytics.percent_format", event.previousRemainingPercent)
        let current = L10n.text("usage_analytics.percent_format", event.currentRemainingPercent)
        let time = event.timestamp.formatted(.dateTime.locale(L10n.locale()).month().day().hour().minute())
        return L10n.text("usage_analytics.threshold.detail", previous, current, time)
    }

    private func anomalyColor(for severity: UsageAnalyticsAnomaly.Severity) -> Color {
        switch severity {
        case .critical:
            return PoolDashboardTheme.danger
        case .warning:
            return PoolDashboardTheme.warning
        case .info:
            return PoolDashboardTheme.textSecondary
        }
    }

    private func etaSubtitle(_ eta: UsageAnalyticsETA) -> String {
        let remaining = L10n.text("usage_analytics.percent_format", eta.remainingPercent)
        return L10n.text(
            "usage_analytics.eta.subtitle",
            remaining,
            String(format: "%.1f", eta.burnPerHour)
        )
    }

    private func etaValueText(_ eta: UsageAnalyticsETA) -> String {
        guard let hours = eta.etaHours else {
            return L10n.text("usage_analytics.not_available")
        }
        if hours < 1 {
            return L10n.text("usage_analytics.eta.less_than_hour")
        }
        return L10n.text("usage_analytics.eta.hours", Int(hours.rounded()))
    }

    private func ratioText(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }

    private var bestRemainingAccountText: String {
        let pairs = deduplicatedAccountsByKey.map { key, account in
            (key: key, name: account.name, remaining: max(0, min(100, Int((account.remainingRatio * 100).rounded()))))
        }
        guard let best = pairs.max(by: { lhs, rhs in lhs.remaining < rhs.remaining }) else {
            return L10n.text("usage_analytics.not_available")
        }
        return "\(best.name) · \(best.remaining)%"
    }

    private var lowestRemainingAccountText: String {
        let pairs = deduplicatedAccountsByKey.map { key, account in
            (key: key, name: account.name, remaining: max(0, min(100, Int((account.remainingRatio * 100).rounded()))))
        }
        guard let lowest = pairs.min(by: { lhs, rhs in lhs.remaining < rhs.remaining }) else {
            return L10n.text("usage_analytics.not_available")
        }
        return "\(lowest.name) · \(lowest.remaining)%"
    }

    private func dailyRemainingSeries(days: Int) -> [UsageAnalyticsDailyTotal] {
        guard days > 0 else { return [] }
        let calendar = Calendar.autoupdatingCurrent
        let todayStart = calendar.startOfDay(for: Date())
        var totals: [UsageAnalyticsDailyTotal] = []

        for dayOffset in stride(from: days - 1, through: 0, by: -1) {
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: todayStart),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                continue
            }

            let records = analyticsState.records.filter {
                $0.timestamp >= dayStart
                && $0.timestamp < dayEnd
                && (selectedAccountKey == nil || $0.accountKey == selectedAccountKey)
            }

            let value: Int
            if records.isEmpty {
                value = remainingFallbackValue(accountKey: selectedAccountKey)
            } else if let selectedAccountKey {
                let latest = records
                    .filter { $0.accountKey == selectedAccountKey }
                    .max(by: { $0.timestamp < $1.timestamp })
                value = latest?.weeklyRemainingPercent ?? remainingFallbackValue(accountKey: selectedAccountKey)
            } else {
                let latestByKey = Dictionary(grouping: records, by: \.accountKey).compactMapValues { bucket in
                    bucket.max(by: { $0.timestamp < $1.timestamp })?.weeklyRemainingPercent
                }
                if latestByKey.isEmpty {
                    value = remainingFallbackValue(accountKey: nil)
                } else {
                    let average = Double(latestByKey.values.reduce(0, +)) / Double(latestByKey.count)
                    value = Int(average.rounded())
                }
            }

            totals.append(UsageAnalyticsDailyTotal(date: dayStart, totalWeeklyPercent: max(0, min(100, value))))
        }

        return totals
    }

    private func weeklyRemainingSeries(weeks: Int) -> [UsageAnalyticsWeeklyTotal] {
        guard weeks > 0 else { return [] }
        let calendar = Calendar.autoupdatingCurrent
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        var totals: [UsageAnalyticsWeeklyTotal] = []

        for weekOffset in stride(from: weeks - 1, through: 0, by: -1) {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: currentWeek.start),
                  let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                continue
            }

            let records = analyticsState.records.filter {
                $0.timestamp >= weekStart
                && $0.timestamp < weekEnd
                && (selectedAccountKey == nil || $0.accountKey == selectedAccountKey)
            }

            let value: Int
            if records.isEmpty {
                value = remainingFallbackValue(accountKey: selectedAccountKey)
            } else if let selectedAccountKey {
                let latest = records
                    .filter { $0.accountKey == selectedAccountKey }
                    .max(by: { $0.timestamp < $1.timestamp })
                value = latest?.weeklyRemainingPercent ?? remainingFallbackValue(accountKey: selectedAccountKey)
            } else {
                let latestByKey = Dictionary(grouping: records, by: \.accountKey).compactMapValues { bucket in
                    bucket.max(by: { $0.timestamp < $1.timestamp })?.weeklyRemainingPercent
                }
                if latestByKey.isEmpty {
                    value = remainingFallbackValue(accountKey: nil)
                } else {
                    let average = Double(latestByKey.values.reduce(0, +)) / Double(latestByKey.count)
                    value = Int(average.rounded())
                }
            }

            totals.append(
                UsageAnalyticsWeeklyTotal(
                    weekStartDate: weekStart,
                    totalWeeklyPercent: max(0, min(100, value))
                )
            )
        }

        return totals
    }

    private func dailyWastedSeries(days: Int) -> [UsageAnalyticsDailyTotal] {
        guard days > 0 else { return [] }
        let calendar = Calendar.autoupdatingCurrent
        let todayStart = calendar.startOfDay(for: Date())
        var totals: [UsageAnalyticsDailyTotal] = []

        for dayOffset in stride(from: days - 1, through: 0, by: -1) {
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: todayStart),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                continue
            }

            let total = analyticsState.records
                .filter {
                    $0.timestamp >= dayStart
                    && $0.timestamp < dayEnd
                    && (selectedAccountKey == nil || $0.accountKey == selectedAccountKey)
                }
                .reduce(0) { partial, record in
                    partial + max(0, record.weeklyWastedPercent)
                }

            totals.append(UsageAnalyticsDailyTotal(date: dayStart, totalWeeklyPercent: total))
        }

        return totals
    }

    private func weeklyWastedSeries(weeks: Int) -> [UsageAnalyticsWeeklyTotal] {
        guard weeks > 0 else { return [] }
        let calendar = Calendar.autoupdatingCurrent
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        var totals: [UsageAnalyticsWeeklyTotal] = []

        for weekOffset in stride(from: weeks - 1, through: 0, by: -1) {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: currentWeek.start),
                  let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                continue
            }

            let total = analyticsState.records
                .filter {
                    $0.timestamp >= weekStart
                    && $0.timestamp < weekEnd
                    && (selectedAccountKey == nil || $0.accountKey == selectedAccountKey)
                }
                .reduce(0) { partial, record in
                    partial + max(0, record.weeklyWastedPercent)
                }

            totals.append(
                UsageAnalyticsWeeklyTotal(
                    weekStartDate: weekStart,
                    totalWeeklyPercent: total
                )
            )
        }

        return totals
    }

    private func dailyIdleDelaySeries(days: Int) -> [UsageAnalyticsDailyTotal] {
        guard days > 0 else { return [] }
        let calendar = Calendar.autoupdatingCurrent
        let todayStart = calendar.startOfDay(for: Date())
        var totals: [UsageAnalyticsDailyTotal] = []

        for dayOffset in stride(from: days - 1, through: 0, by: -1) {
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: todayStart),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                continue
            }

            let total = analyticsState.records
                .filter {
                    $0.timestamp >= dayStart
                    && $0.timestamp < dayEnd
                    && (selectedAccountKey == nil || $0.accountKey == selectedAccountKey)
                }
                .reduce(0) { partial, record in
                    partial + max(0, record.weeklyIdleDelayMinutes)
                }

            totals.append(UsageAnalyticsDailyTotal(date: dayStart, totalWeeklyPercent: total))
        }

        return totals
    }

    private func weeklyIdleDelaySeries(weeks: Int) -> [UsageAnalyticsWeeklyTotal] {
        guard weeks > 0 else { return [] }
        let calendar = Calendar.autoupdatingCurrent
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        var totals: [UsageAnalyticsWeeklyTotal] = []

        for weekOffset in stride(from: weeks - 1, through: 0, by: -1) {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: currentWeek.start),
                  let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                continue
            }

            let total = analyticsState.records
                .filter {
                    $0.timestamp >= weekStart
                    && $0.timestamp < weekEnd
                    && (selectedAccountKey == nil || $0.accountKey == selectedAccountKey)
                }
                .reduce(0) { partial, record in
                    partial + max(0, record.weeklyIdleDelayMinutes)
                }

            totals.append(
                UsageAnalyticsWeeklyTotal(
                    weekStartDate: weekStart,
                    totalWeeklyPercent: total
                )
            )
        }

        return totals
    }

    private func remainingFallbackValue(accountKey: String?) -> Int {
        if let accountKey {
            if let snapshot = analyticsState.snapshots.first(where: { $0.accountKey == accountKey }) {
                return max(0, min(100, 100 - snapshot.lastWeeklyPercent))
            }
            if let account = deduplicatedAccountsByKey[accountKey] {
                return max(0, min(100, Int((account.remainingRatio * 100).rounded())))
            }
            return 0
        }

        return averageWeeklyRemainingPercent
    }

    private func copyJSONReportToClipboard() {
        let report = UsageAnalyticsEngine.jsonReport(
            state: analyticsState,
            accounts: accounts,
            activeAccountKey: analyticsState.lastActiveAccountKey,
            now: Date()
        )
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        exportStatus = (L10n.text("usage_analytics.export.success.copy_json"), .success)
        #else
        exportStatus = (L10n.text("usage_analytics.export.failure.copy_json"), .danger)
        #endif
    }

    private func exportCSVReport() {
        let content = UsageAnalyticsEngine.csvReport(state: analyticsState, accounts: accounts)
        let success = saveReport(
            content: content,
            filename: "usage-analytics-\(timestampForFilename())",
            fileExtension: "csv"
        )
        exportStatus = (
            success ? L10n.text("usage_analytics.export.success.csv") : L10n.text("usage_analytics.export.failure.csv"),
            success ? .success : .danger
        )
    }

    private func exportJSONReport() {
        let content = UsageAnalyticsEngine.jsonReport(
            state: analyticsState,
            accounts: accounts,
            activeAccountKey: analyticsState.lastActiveAccountKey,
            now: Date()
        )
        let success = saveReport(
            content: content,
            filename: "usage-analytics-\(timestampForFilename())",
            fileExtension: "json"
        )
        exportStatus = (
            success ? L10n.text("usage_analytics.export.success.json") : L10n.text("usage_analytics.export.failure.json"),
            success ? .success : .danger
        )
    }

    private func saveReport(content: String, filename: String, fileExtension: String) -> Bool {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(filename).\(fileExtension)"
        if #available(macOS 12.0, *) {
            if let contentType = UTType(filenameExtension: fileExtension) {
                panel.allowedContentTypes = [contentType]
            }
        } else {
            panel.allowedFileTypes = [fileExtension]
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    private func timestampForFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

private struct UsageAnalyticsStableDetailSectionsView: View, Equatable {
    let analyticsState: UsageAnalyticsState
    let accounts: [AgentAccount]
    let selectedAccountKey: String?
    @State private var exportStatus: (message: String, tone: PanelStatusCalloutView.Tone)? = nil

    static func == (lhs: UsageAnalyticsStableDetailSectionsView, rhs: UsageAnalyticsStableDetailSectionsView) -> Bool {
        lhs.renderIdentity == rhs.renderIdentity
    }

    private var renderIdentity: String {
        var parts: [String] = []
        parts.reserveCapacity(8)
        parts.append(selectedAccountKey ?? "all")
        parts.append(String(analyticsState.records.count))
        parts.append(String(analyticsState.snapshots.count))
        parts.append(String(analyticsState.thresholdEvents.count))
        parts.append(String(analyticsState.switchEvents.count))
        parts.append(analyticsState.lastUpdatedAt?.timeIntervalSince1970.description ?? "never")
        parts.append(String(accounts.count))
        parts.append(accountRenderIdentity)
        return parts.joined(separator: "#")
    }

    private var accountRenderIdentity: String {
        accounts
            .map { account in
                "\(account.usageAnalyticsAccountKey)=\(account.name)"
            }
            .joined(separator: "|")
    }

    var body: some View {
        operationsView
        coverageAndSwitchView
        recommendationView
        thresholdAndAnomalyView
        etaView
    }

    private var accountNameByKey: [String: String] {
        var mapping: [String: String] = [:]
        for account in accounts where mapping[account.usageAnalyticsAccountKey] == nil {
            mapping[account.usageAnalyticsAccountKey] = account.name
        }
        return mapping
    }

    private var etasByAccountKey: [String: UsageAnalyticsETA] {
        UsageAnalyticsEngine.etas(
            accounts: accounts,
            state: analyticsState,
            now: Date()
        )
    }

    private var sortedETAs: [UsageAnalyticsETA] {
        etasByAccountKey
            .values
            .sorted { lhs, rhs in
                if lhs.remainingPercent != rhs.remainingPercent {
                    return lhs.remainingPercent > rhs.remainingPercent
                }
                return lhs.accountKey.localizedCaseInsensitiveCompare(rhs.accountKey) == .orderedAscending
            }
    }

    private var displayedETAs: [UsageAnalyticsETA] {
        if let selectedAccountKey {
            return sortedETAs.filter { $0.accountKey == selectedAccountKey }
        }
        return Array(sortedETAs.prefix(6))
    }

    private var thresholdEvents: [UsageAnalyticsThresholdEvent] {
        UsageAnalyticsEngine.thresholdTimeline(
            for: analyticsState,
            accountKey: selectedAccountKey,
            limit: 8
        )
    }

    private var switchEffectiveness: UsageAnalyticsSwitchEffectiveness {
        UsageAnalyticsEngine.switchEffectiveness(for: analyticsState)
    }

    private var coverageSummary: UsageAnalyticsCoverageSummary {
        UsageAnalyticsEngine.projectedCoverage(accounts: accounts, now: Date())
    }

    private var anomalyEvents: [UsageAnalyticsAnomaly] {
        UsageAnalyticsEngine.anomalies(
            state: analyticsState,
            accounts: accounts,
            now: Date()
        )
    }

    private var recommendation: UsageAnalyticsRecommendation {
        UsageAnalyticsEngine.recommendation(
            accounts: accounts,
            activeAccountKey: analyticsState.lastActiveAccountKey,
            etasByAccountKey: etasByAccountKey
        )
    }

    private var operationsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L10n.text("usage_analytics.section.export"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textPrimary)

                Spacer(minLength: 0)

                Button(L10n.text("usage_analytics.export.copy_json")) {
                    copyJSONReportToClipboard()
                }
                .buttonStyle(.bordered)

                Button(L10n.text("usage_analytics.export.csv")) {
                    exportCSVReport()
                }
                .buttonStyle(.bordered)

                Button(L10n.text("usage_analytics.export.json")) {
                    exportJSONReport()
                }
                .buttonStyle(.bordered)
            }

            if let exportStatus {
                PanelStatusCalloutView(
                    message: exportStatus.message,
                    tone: exportStatus.tone
                )
            }
        }
        .dashboardInfoCard()
    }

    private var coverageAndSwitchView: some View {
        HStack(spacing: 8) {
            summaryCard(
                title: L10n.text("usage_analytics.summary.coverage"),
                value: ratioText(coverageSummary.coveredRatio)
            )
            summaryCard(
                title: L10n.text("usage_analytics.summary.uncovered_slots"),
                value: "\(coverageSummary.uncoveredSlots)/\(coverageSummary.totalSlots)"
            )
            summaryCard(
                title: L10n.text("usage_analytics.summary.switch_gain"),
                value: String(format: "%.1f%%", switchEffectiveness.averageRemainingGain)
            )
            summaryCard(
                title: L10n.text("usage_analytics.summary.switch_improved"),
                value: ratioText(switchEffectiveness.improvedRate)
            )
        }
    }

    private var recommendationView: some View {
        let targetName = recommendation.targetAccountKey.flatMap { accountNameByKey[$0] ?? $0 }
        let titleKey = targetName == nil ? "usage_analytics.recommendation.none" : "usage_analytics.recommendation.title"
        let message = targetName.map { "\($0) · \(recommendation.reason)" } ?? recommendation.reason
        return PanelStatusCalloutView(
            message: message,
            title: L10n.text(titleKey),
            tone: recommendation.targetAccountKey == nil ? .info : .success
        )
    }

    private var thresholdAndAnomalyView: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("usage_analytics.section.thresholds"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textPrimary)

                if thresholdEvents.isEmpty {
                    Text(L10n.text("usage_analytics.empty_thresholds"))
                        .font(.footnote)
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                } else {
                    ForEach(thresholdEvents) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(thresholdEventHeadline(event))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(PoolDashboardTheme.textSecondary)
                            Text(thresholdEventDetail(event))
                                .font(.caption)
                                .foregroundStyle(PoolDashboardTheme.textMuted)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dashboardInfoCard()

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("usage_analytics.section.anomalies"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textPrimary)

                if anomalyEvents.isEmpty {
                    Text(L10n.text("usage_analytics.empty_anomalies"))
                        .font(.footnote)
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                } else {
                    ForEach(anomalyEvents.prefix(6)) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(anomalyColor(for: event.severity))
                            Text(event.detail)
                                .font(.caption)
                                .foregroundStyle(PoolDashboardTheme.textMuted)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dashboardInfoCard()
        }
    }

    private var etaView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("usage_analytics.section.eta"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PoolDashboardTheme.textPrimary)

            if sortedETAs.isEmpty {
                Text(L10n.text("usage_analytics.empty_eta"))
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)
            } else {
                ForEach(displayedETAs, id: \.accountKey) { eta in
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(accountNameByKey[eta.accountKey] ?? eta.accountKey)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(PoolDashboardTheme.textSecondary)
                                .lineLimit(1)
                            Text(etaSubtitle(eta))
                                .font(.caption)
                                .foregroundStyle(PoolDashboardTheme.textMuted)
                        }

                        Spacer(minLength: 0)

                        Text(etaValueText(eta))
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(PoolDashboardTheme.textPrimary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .dashboardInfoCard()
    }

    private func summaryCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PoolDashboardTheme.textMuted)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PoolDashboardTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardInfoCard()
    }

    private func thresholdEventHeadline(_ event: UsageAnalyticsThresholdEvent) -> String {
        let kind = event.kind == .weekly
            ? L10n.text("usage_analytics.threshold.weekly")
            : L10n.text("usage_analytics.threshold.five_hour")
        let account = accountNameByKey[event.accountKey] ?? event.accountKey
        return L10n.text("usage_analytics.threshold.headline", account, kind, event.thresholdPercent)
    }

    private func thresholdEventDetail(_ event: UsageAnalyticsThresholdEvent) -> String {
        let previous = L10n.text("usage_analytics.percent_format", event.previousRemainingPercent)
        let current = L10n.text("usage_analytics.percent_format", event.currentRemainingPercent)
        let time = event.timestamp.formatted(.dateTime.locale(L10n.locale()).month().day().hour().minute())
        return L10n.text("usage_analytics.threshold.detail", previous, current, time)
    }

    private func anomalyColor(for severity: UsageAnalyticsAnomaly.Severity) -> Color {
        switch severity {
        case .critical:
            return PoolDashboardTheme.danger
        case .warning:
            return PoolDashboardTheme.warning
        case .info:
            return PoolDashboardTheme.textSecondary
        }
    }

    private func etaSubtitle(_ eta: UsageAnalyticsETA) -> String {
        let remaining = L10n.text("usage_analytics.percent_format", eta.remainingPercent)
        return L10n.text(
            "usage_analytics.eta.subtitle",
            remaining,
            String(format: "%.1f", eta.burnPerHour)
        )
    }

    private func etaValueText(_ eta: UsageAnalyticsETA) -> String {
        guard let hours = eta.etaHours else {
            return L10n.text("usage_analytics.not_available")
        }
        if hours < 1 {
            return L10n.text("usage_analytics.eta.less_than_hour")
        }
        return L10n.text("usage_analytics.eta.hours", Int(hours.rounded()))
    }

    private func ratioText(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }

    private func copyJSONReportToClipboard() {
        let report = UsageAnalyticsEngine.jsonReport(
            state: analyticsState,
            accounts: accounts,
            activeAccountKey: analyticsState.lastActiveAccountKey,
            now: Date()
        )
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        exportStatus = (L10n.text("usage_analytics.export.success.copy_json"), .success)
        #else
        exportStatus = (L10n.text("usage_analytics.export.failure.copy_json"), .danger)
        #endif
    }

    private func exportCSVReport() {
        let content = UsageAnalyticsEngine.csvReport(state: analyticsState, accounts: accounts)
        let success = saveReport(
            content: content,
            filename: "usage-analytics-\(timestampForFilename())",
            fileExtension: "csv"
        )
        exportStatus = (
            success ? L10n.text("usage_analytics.export.success.csv") : L10n.text("usage_analytics.export.failure.csv"),
            success ? .success : .danger
        )
    }

    private func exportJSONReport() {
        let content = UsageAnalyticsEngine.jsonReport(
            state: analyticsState,
            accounts: accounts,
            activeAccountKey: analyticsState.lastActiveAccountKey,
            now: Date()
        )
        let success = saveReport(
            content: content,
            filename: "usage-analytics-\(timestampForFilename())",
            fileExtension: "json"
        )
        exportStatus = (
            success ? L10n.text("usage_analytics.export.success.json") : L10n.text("usage_analytics.export.failure.json"),
            success ? .success : .danger
        )
    }

    private func saveReport(content: String, filename: String, fileExtension: String) -> Bool {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(filename).\(fileExtension)"
        if #available(macOS 12.0, *) {
            if let contentType = UTType(filenameExtension: fileExtension) {
                panel.allowedContentTypes = [contentType]
            }
        } else {
            panel.allowedFileTypes = [fileExtension]
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    private func timestampForFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

private enum DesktopNotifier {
    private static let lock = NSLock()
    private static var didRequestAuthorization = false
    private static var didConfigureCenter = false
    private static var lastSentAtByKey: [String: Date] = [:]
    private static let delegate = NotificationCenterDelegate()

    static func requestAuthorizationIfNeeded() {
        configureCenterIfNeeded()

        lock.lock()
        guard !didRequestAuthorization else {
            lock.unlock()
            return
        }
        didRequestAuthorization = true
        lock.unlock()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("DesktopNotifier authorization failed: \(error.localizedDescription)")
                return
            }
            if !granted {
                NSLog("DesktopNotifier authorization denied by user.")
            }
        }
    }

    static func post(
        key: String,
        title: String,
        body: String,
        minInterval: TimeInterval
    ) {
        configureCenterIfNeeded()
        guard shouldPost(key: key, minInterval: minInterval) else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "codexpool.notification.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("DesktopNotifier post failed: \(error.localizedDescription)")
            }
        }
    }

    private static func shouldPost(key: String, minInterval: TimeInterval) -> Bool {
        let now = Date()
        lock.lock()
        defer { lock.unlock() }

        if minInterval > 0,
           let last = lastSentAtByKey[key],
           now.timeIntervalSince(last) < minInterval {
            return false
        }
        lastSentAtByKey[key] = now
        return true
    }

    private static func configureCenterIfNeeded() {
        lock.lock()
        guard !didConfigureCenter else {
            lock.unlock()
            return
        }
        didConfigureCenter = true
        lock.unlock()

        UNUserNotificationCenter.current().delegate = delegate
    }

    private final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            completionHandler([.banner, .list, .sound])
        }
    }
}

#if DEBUG
extension DesktopNotifier {
    static func debugThrottleSequence(
        key: String = "debug.notifier",
        minInterval: TimeInterval
    ) -> (first: Bool, second: Bool, afterReset: Bool) {
        lock.lock()
        lastSentAtByKey.removeAll()
        lock.unlock()

        let first = shouldPost(key: key, minInterval: minInterval)
        let second = shouldPost(key: key, minInterval: minInterval)

        lock.lock()
        lastSentAtByKey.removeAll()
        lock.unlock()

        let afterReset = shouldPost(key: key, minInterval: minInterval)
        return (first, second, afterReset)
    }
}

struct ScheduleEventDebugSummary: Equatable {
    let accountID: UUID
    let accountName: String
    let date: Date
    let kindID: String
}

private extension ScheduleWorkspacePanelView {
    @MainActor
    static func debugEventSummaries(
        accounts: [AgentAccount],
        start: Date,
        end: Date
    ) -> [ScheduleEventDebugSummary] {
        ScheduleWorkspacePanelView(accounts: accounts)
            .buildEvents(from: start, to: end)
            .map { event in
                ScheduleEventDebugSummary(
                    accountID: event.accountID,
                    accountName: event.accountName,
                    date: event.date,
                    kindID: event.kind == .weekly ? "weekly" : "fiveHour"
                )
            }
    }
}

private extension DailyUsagePlanningWorkspacePanelView {
    private static var debugStorageKeys: [String] {
        [
            "pool_dashboard.schedule.weekly_account_limits",
            "pool_dashboard.schedule.selected_weekday",
            "pool_dashboard.schedule.daily_plan_enabled",
            "pool_dashboard.schedule.daily_plan_notify_enabled",
            "pool_dashboard.schedule.daily_plan_warning_threshold_percent",
            "pool_dashboard.schedule.daily_plan_notified_days"
        ]
    }

    @MainActor
    static func debugNotificationBodies(account: AgentAccount) -> [String: String] {
        let now = Date()
        let accountKey = account.deduplicationKey
        let weekday = DailyUsagePlanEvaluator.weekdayKey(for: now)
        let defaults = UserDefaults.standard
        let backupValues = Dictionary(uniqueKeysWithValues: debugStorageKeys.map { key in
            (key, defaults.object(forKey: key))
        })
        defer {
            for key in debugStorageKeys {
                if let original = backupValues[key] {
                    defaults.set(original, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        func body(plannedLimit: Int, usedPercent: Int) -> String {
            let budgetMap = [weekday: [accountKey: plannedLimit]]
            let budgetJSON = (try? JSONEncoder().encode(budgetMap))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            defaults.set(budgetJSON, forKey: "pool_dashboard.schedule.weekly_account_limits")
            defaults.set(weekday, forKey: "pool_dashboard.schedule.selected_weekday")
            defaults.set(true, forKey: "pool_dashboard.schedule.daily_plan_enabled")
            defaults.set(true, forKey: "pool_dashboard.schedule.daily_plan_notify_enabled")
            defaults.set(80, forKey: "pool_dashboard.schedule.daily_plan_warning_threshold_percent")
            defaults.set("{}", forKey: "pool_dashboard.schedule.daily_plan_notified_days")

            let state = UsageAnalyticsState(
                records: [
                    UsageAnalyticsRecord(
                        timestamp: now,
                        accountKey: accountKey,
                        weeklyDeltaPercent: usedPercent,
                        fiveHourDeltaPercent: 0
                    )
                ],
                snapshots: [],
                thresholdEvents: [],
                switchEvents: [],
                lastActiveAccountKey: accountKey,
                lastUpdatedAt: now
            )
            let view = DailyUsagePlanningWorkspacePanelView(
                accounts: [account],
                analyticsState: state
            )
            return view.notificationBody
        }

        return [
            "none": body(plannedLimit: 50, usedPercent: 10),
            "warning": body(plannedLimit: 50, usedPercent: 42),
            "exceeded": body(plannedLimit: 50, usedPercent: 51)
        ]
    }

    @MainActor
    static func debugNotificationTitles(account: AgentAccount) -> [String: String] {
        let now = Date()
        let accountKey = account.deduplicationKey
        let weekday = DailyUsagePlanEvaluator.weekdayKey(for: now)
        let defaults = UserDefaults.standard
        let backupValues = Dictionary(uniqueKeysWithValues: debugStorageKeys.map { key in
            (key, defaults.object(forKey: key))
        })
        defer {
            for key in debugStorageKeys {
                if let original = backupValues[key] {
                    defaults.set(original, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        func title(plannedLimit: Int, usedPercent: Int) -> String {
            let budgetMap = [weekday: [accountKey: plannedLimit]]
            let budgetJSON = (try? JSONEncoder().encode(budgetMap))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            defaults.set(budgetJSON, forKey: "pool_dashboard.schedule.weekly_account_limits")
            defaults.set(weekday, forKey: "pool_dashboard.schedule.selected_weekday")
            defaults.set(true, forKey: "pool_dashboard.schedule.daily_plan_enabled")
            defaults.set(true, forKey: "pool_dashboard.schedule.daily_plan_notify_enabled")
            defaults.set(80, forKey: "pool_dashboard.schedule.daily_plan_warning_threshold_percent")
            defaults.set("{}", forKey: "pool_dashboard.schedule.daily_plan_notified_days")

            let state = UsageAnalyticsState(
                records: [
                    UsageAnalyticsRecord(
                        timestamp: now,
                        accountKey: accountKey,
                        weeklyDeltaPercent: usedPercent,
                        fiveHourDeltaPercent: 0
                    )
                ],
                snapshots: [],
                thresholdEvents: [],
                switchEvents: [],
                lastActiveAccountKey: accountKey,
                lastUpdatedAt: now
            )
            let view = DailyUsagePlanningWorkspacePanelView(
                accounts: [account],
                analyticsState: state
            )
            return view.notificationTitle
        }

        return [
            "none": title(plannedLimit: 50, usedPercent: 10),
            "warning": title(plannedLimit: 50, usedPercent: 42),
            "exceeded": title(plannedLimit: 50, usedPercent: 51)
        ]
    }

    @MainActor
    static func debugBudgetPersistenceProbe(
        account: AgentAccount
    ) -> (afterSetBudget: Int?, afterClearBudget: Int?, notifiedLevel: String?) {
        let accountKey = account.deduplicationKey
        let weekday = DailyUsagePlanEvaluator.weekdayKey(for: Date())
        let defaults = UserDefaults.standard
        let backupValues = Dictionary(uniqueKeysWithValues: debugStorageKeys.map { key in
            (key, defaults.object(forKey: key))
        })
        defer {
            for key in debugStorageKeys {
                if let original = backupValues[key] {
                    defaults.set(original, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set("{}", forKey: "pool_dashboard.schedule.weekly_account_limits")
        defaults.set(weekday, forKey: "pool_dashboard.schedule.selected_weekday")
        defaults.set("{}", forKey: "pool_dashboard.schedule.daily_plan_notified_days")

        let view = DailyUsagePlanningWorkspacePanelView(
            accounts: [account],
            analyticsState: UsageAnalyticsState()
        )
        let budgetBinding = view.weekdayBudgetBinding(for: accountKey)
        budgetBinding.wrappedValue = 35
        let afterSetBudget = decodedWeeklyBudgetMap(from: defaults)[weekday]?[accountKey]
        budgetBinding.wrappedValue = 0
        let afterClearBudget = decodedWeeklyBudgetMap(from: defaults)[weekday]?[accountKey]

        view.persistNotifiedDays(["debug": "warning"])
        let notifiedLevel = decodedNotifiedDays(from: defaults)["debug"]

        return (afterSetBudget, afterClearBudget, notifiedLevel)
    }

    @MainActor
    static func debugStatusCallouts(account: AgentAccount) -> some View {
        let now = Date()
        let accountKey = account.deduplicationKey
        let weekday = DailyUsagePlanEvaluator.weekdayKey(for: now)
        let defaults = UserDefaults.standard
        let backupValues = Dictionary(uniqueKeysWithValues: debugStorageKeys.map { key in
            (key, defaults.object(forKey: key))
        })
        defer {
            for key in debugStorageKeys {
                if let original = backupValues[key] {
                    defaults.set(original, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        func callout(plannedLimit: Int?, usedPercent: Int) -> some View {
            let budgetMap: [String: [String: Int]]
            if let plannedLimit {
                budgetMap = [weekday: [accountKey: plannedLimit]]
            } else {
                budgetMap = [weekday: [:]]
            }
            let budgetJSON = (try? JSONEncoder().encode(budgetMap))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            defaults.set(budgetJSON, forKey: "pool_dashboard.schedule.weekly_account_limits")
            defaults.set(weekday, forKey: "pool_dashboard.schedule.selected_weekday")
            defaults.set(true, forKey: "pool_dashboard.schedule.daily_plan_enabled")
            defaults.set(true, forKey: "pool_dashboard.schedule.daily_plan_notify_enabled")
            defaults.set(80, forKey: "pool_dashboard.schedule.daily_plan_warning_threshold_percent")
            defaults.set("{}", forKey: "pool_dashboard.schedule.daily_plan_notified_days")

            let state = UsageAnalyticsState(
                records: [
                    UsageAnalyticsRecord(
                        timestamp: now,
                        accountKey: accountKey,
                        weeklyDeltaPercent: usedPercent,
                        fiveHourDeltaPercent: 0
                    )
                ],
                snapshots: [],
                thresholdEvents: [],
                switchEvents: [],
                lastActiveAccountKey: accountKey,
                lastUpdatedAt: now
            )
            let view = DailyUsagePlanningWorkspacePanelView(
                accounts: [account],
                analyticsState: state
            )
            return view.planStatusCallout
        }

        return VStack(alignment: .leading, spacing: 8) {
            callout(plannedLimit: nil, usedPercent: 0)
            callout(plannedLimit: 50, usedPercent: 10)
            callout(plannedLimit: 50, usedPercent: 42)
            callout(plannedLimit: 50, usedPercent: 51)
        }
    }

    @MainActor
    static func debugNotificationEvaluationProbe() -> DailyUsagePlanningNotificationEvaluationDebugProbe {
        let now = Date()
        let account = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000DA11")!,
            name: "daily-plan@example.com",
            usedUnits: 0,
            quota: 100,
            chatGPTAccountID: "daily-plan"
        )
        let accountKey = account.deduplicationKey
        let weekday = DailyUsagePlanEvaluator.weekdayKey(for: now)
        let defaults = UserDefaults.standard
        let backupValues = Dictionary(uniqueKeysWithValues: debugStorageKeys.map { key in
            (key, defaults.object(forKey: key))
        })
        defer {
            for key in debugStorageKeys {
                if let original = backupValues[key] {
                    defaults.set(original, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        func encoded<T: Encodable>(_ value: T) -> String {
            (try? JSONEncoder().encode(value))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        }

        func configure(
            enabled: Bool = true,
            notifyEnabled: Bool = true,
            notifiedDays: [String: String] = [:]
        ) {
            defaults.set(encoded([weekday: [accountKey: 50]]), forKey: "pool_dashboard.schedule.weekly_account_limits")
            defaults.set(weekday, forKey: "pool_dashboard.schedule.selected_weekday")
            defaults.set(enabled, forKey: "pool_dashboard.schedule.daily_plan_enabled")
            defaults.set(notifyEnabled, forKey: "pool_dashboard.schedule.daily_plan_notify_enabled")
            defaults.set(80, forKey: "pool_dashboard.schedule.daily_plan_warning_threshold_percent")
            defaults.set(encoded(notifiedDays), forKey: "pool_dashboard.schedule.daily_plan_notified_days")
        }

        func analyticsState(usedPercent: Int) -> UsageAnalyticsState {
            UsageAnalyticsState(
                records: [
                    UsageAnalyticsRecord(
                        timestamp: now,
                        accountKey: accountKey,
                        weeklyDeltaPercent: usedPercent,
                        fiveHourDeltaPercent: 0
                    )
                ],
                snapshots: [],
                thresholdEvents: [],
                switchEvents: [],
                lastActiveAccountKey: accountKey,
                lastUpdatedAt: now
            )
        }

        func view(usedPercent: Int) -> DailyUsagePlanningWorkspacePanelView {
            DailyUsagePlanningWorkspacePanelView(
                accounts: [account],
                analyticsState: analyticsState(usedPercent: usedPercent)
            )
        }

        configure()
        let notifyingView = view(usedPercent: 42)
        let notifyRequest = notifyingView.dailyPlanNotificationRequestIfNeeded(now: now)
        if let notifyRequest {
            notifyingView.persistNotifiedDays(notifyRequest.markedNotifiedDays)
        }
        let persistedLevel = decodedNotifiedDays(from: defaults)
            .keys
            .compactMap { $0.split(separator: "|").last.map(String.init) }
            .first

        configure(enabled: false)
        let disabledPlanDidNotify = view(usedPercent: 42).dailyPlanNotificationRequestIfNeeded(now: now) != nil

        configure(notifiedDays: notifyRequest?.markedNotifiedDays ?? [:])
        let alreadyNotifiedDidNotify = view(usedPercent: 42).dailyPlanNotificationRequestIfNeeded(now: now) != nil

        return DailyUsagePlanningNotificationEvaluationDebugProbe(
            notifyRequestKey: notifyRequest?.key ?? "",
            notifyTitle: notifyRequest?.title ?? "",
            notifyBody: notifyRequest?.body ?? "",
            notifyPersistedLevel: persistedLevel,
            disabledPlanDidNotify: disabledPlanDidNotify,
            alreadyNotifiedDidNotify: alreadyNotifiedDidNotify
        )
    }

    private static func decodedWeeklyBudgetMap(from defaults: UserDefaults) -> [String: [String: Int]] {
        guard let rawValue = defaults.string(forKey: "pool_dashboard.schedule.weekly_account_limits"),
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private static func decodedNotifiedDays(from defaults: UserDefaults) -> [String: String] {
        guard let rawValue = defaults.string(forKey: "pool_dashboard.schedule.daily_plan_notified_days"),
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return decoded
    }
}

struct UsageAnalyticsWorkspaceDebugProbe: Equatable {
    let sortedAccountKeysByMode: [String: [String]]
    let accountMetricSamples: [String: [Int]]
    let dailyRemainingAll: [Int]
    let dailyRemainingSelected: [Int]
    let weeklyRemainingAll: [Int]
    let weeklyRemainingSelected: [Int]
    let dailyWastedAll: [Int]
    let dailyWastedSelected: [Int]
    let weeklyWastedAll: [Int]
    let weeklyWastedSelected: [Int]
    let dailyIdleDelayAll: [Int]
    let dailyIdleDelaySelected: [Int]
    let weeklyIdleDelayAll: [Int]
    let weeklyIdleDelaySelected: [Int]
    let analysisDescriptions: [String: String]
    let chartEntryCounts: [String: Int]
    let chartValueLabels: [String: String]
    let etaValueTexts: [String]
}

struct SpecialResetPresentationDebugProbe: Equatable {
    let accountRecordWeeklyText: String
    let accountRecordFiveHourText: String
    let fallbackRecordWeeklyText: String
    let fallbackRecordFiveHourText: String
    let unavailableWeeklyText: String
    let unavailableFiveHourText: String
    let eventMessage: String
    let eventDateTexts: [String]
}

struct SpecialResetBaselineDebugProbe: Equatable {
    let recordNames: [String]
    let expectedWeeklyResetAts: [Date?]
    let expectedFiveHourResetAts: [Date?]
    let lastSeenWeeklyUsagePercents: [Int?]
    let lastSeenFiveHourUsagePercents: [Int?]
    let lastSeenAts: [Date?]
    let eventCount: Int
    let lastEvaluatedAt: Date?
}

struct SpecialResetEvaluationDebugProbe: Equatable {
    let recordNames: [String]
    let eventAccountNames: [String]
    let prunedStaleRecord: Bool
    let shouldNotify: Bool
    let lastNotificationAt: Date?
    let lastEvaluatedAt: Date?
}

struct SpecialResetNotificationRequestDebugProbe: Equatable {
    let emptyRequestIsNil: Bool
    let requestKey: String?
    let requestTitle: String
    let requestBodyContainsAccountName: Bool
    let requestBodyContainsObservedDates: Bool
    let requestMinInterval: TimeInterval?
}

struct DailyUsagePlanningNotificationEvaluationDebugProbe: Equatable {
    let notifyRequestKey: String
    let notifyTitle: String
    let notifyBody: String
    let notifyPersistedLevel: String?
    let disabledPlanDidNotify: Bool
    let alreadyNotifiedDidNotify: Bool
}

struct UsageAnalyticsStorageNormalizationDebugProbe: Equatable {
    let didRewriteRawState: Bool
    let storedRecordKeys: [String]
    let loadedRecordKeys: [String]
    let invalidRawReturnedNil: Bool
}

struct UsageAnalyticsStorageLifecycleDebugProbe: Equatable {
    let emptyLoadMarkedLoaded: Bool
    let emptyLoadRecordCount: Int
    let loadedRecordKeys: [String]
    let loadedStateWasPersisted: Bool
    let normalizedLoadedRecordKeys: [String]
    let normalizedRawRecordKeys: [String]
}

struct UsageAnalyticsSyncLifecycleDebugProbe: Equatable {
    let expectedAccountKey: String
    let unloadedSeedSnapshotCount: Int
    let seededSnapshotCount: Int
    let seededActiveAccountKey: String?
    let alreadySeededSnapshotCount: Int
    let unloadedNonAnalyticsUpdateRecordCount: Int
    let unloadedNonAnalyticsMarkedLoaded: Bool
    let workspaceTriggeredUpdateLoadedState: Bool
    let loadedUpdateRecordCount: Int
    let loadedUpdateLastActiveAccountKey: String?
}

struct ManualOAuthPreparationDebugProbe: Equatable {
    let successPendingContextWasStored: Bool
    let successURLContainsAuthorizePath: Bool
    let successMessage: String?
    let successErrorWasCleared: Bool
    let failurePendingContextIsNil: Bool
    let failureErrorIsNotEmpty: Bool
    let failureSuccessMessageIsNil: Bool
}

struct OAuthSignInDebugProbe: Equatable {
    let invalidConfigurationErrorIsNotEmpty: Bool
    let invalidConfigurationSuccessMessageIsNil: Bool
    let invalidConfigurationShouldRefreshLocalAccounts: Bool
}

struct ManualOAuthCallbackDebugProbe: Equatable {
    let missingContextError: String?
    let missingContextSuccessMessageIsNil: Bool
    let invalidCallbackErrorIsNotEmpty: Bool
    let invalidCallbackSuccessMessageIsNil: Bool
    let invalidCallbackShouldRefreshLocalAccounts: Bool
}

struct RelayAccountAdditionDebugProbe: Equatable {
    let addedAccountCount: Int
    let addedAccountIsRelay: Bool
    let relayUsageSyncUnavailable: Bool
    let successMessage: String?
    let errorWasCleared: Bool
}

struct LocalOAuthImportDebugProbe: Equatable {
    let didImportMissingAccountID: Bool
    let accountCountAfterMissingAccountID: Int
    let errorMessage: String?
    let successMessageIsNil: Bool
}

struct ViewMutationWrapperDebugProbe: Equatable {
    let oauthAccountName: String
    let oauthSuccessMessage: String?
    let localImportError: String?
    let pickedAuthFileURLPath: String
    let switchLaunchLog: String
    let switchSessionURLPath: String
}

struct PoolDashboardDataModeReloadDebugProbe: Equatable {
    let loadedAccountNames: [String]
    let loadedSelectedGroupName: String
    let fallbackAccountCount: Int
    let fallbackSelectedGroupName: String
    let actualReloadWasExercised: Bool
}

struct PoolDashboardUsageSyncStuckRecoveryDebugProbe: Equatable {
    let matchingRunIsSyncing: Bool
    let matchingRunIDWasCleared: Bool
    let matchingErrorContainsTimeout: Bool
    let staleRunStayedSyncing: Bool
    let staleRunIDWasPreserved: Bool
}

struct AutomaticSwitchDecisionDebugProbe: Equatable {
    let successMarkedCurrentAccount: Bool
    let successNotificationKeyHasCurrentAccountID: Bool
    let successNotificationMinInterval: TimeInterval?
    let failureMarkedPreviousAccount: Bool
    let failureNotificationKey: String?
    let failureNotificationBody: String?
    let missingPreviousMarkedAccountID: UUID?
    let missingPreviousNotificationKey: String?
}

struct ManualSwitchDecisionDebugProbe: Equatable {
    let missingRoute: String
    let relayRoute: String
    let officialRoute: String
    let successMarkedAccount: Bool
    let successNotificationKeyContainsAccountID: Bool
    let successNotificationMinInterval: TimeInterval?
    let failureNotificationKey: String?
    let failureNotificationBody: String?
    let emptyFailureNotificationKey: String?
}

struct LowUsageAlertTransitionDebugProbe: Equatable {
    let disabledAlertsDidShow: Bool
    let modeChangeDidShow: Bool
    let sameAccountDidShow: Bool
    let thresholdExceededDidShow: Bool
    let thresholdAlertMessageContainsAccountName: Bool
}

struct LowUsageDesktopNotificationDebugProbe: Equatable {
    let disabledAlertsRequestIsNil: Bool
    let previouslyShowingRequestIsNil: Bool
    let hiddenAlertRequestIsNil: Bool
    let explicitMessageKey: String?
    let explicitMessageTitleContainsLowUsage: Bool
    let explicitMessageBody: String?
    let explicitMessageMinInterval: TimeInterval?
    let fallbackMessageContainsAccountName: Bool
}

struct RelaySwitchPreparationDebugProbe: Equatable {
    let preparedHydratedFromVault: Bool
    let preparedRequestUsedVaultAPIKey: Bool
    let preparedRequestAPIKeyLength: Int?
    let preparedDiagnosticContainsPreparedStage: Bool
    let failedDiagnosticContainsPrepareFailedStage: Bool
    let failedErrorDescriptionNotEmpty: Bool
}

struct RelaySwitchOutcomeDecisionDebugProbe: Equatable {
    let successMarkedRelayAccount: Bool
    let successNotificationKeyContainsRelayAccountID: Bool
    let successNotificationBodyContainsRelayAccountName: Bool
    let failureNotificationKey: String?
    let failureNotificationBody: String?
    let emptyFailureNotificationKey: String?
}

struct PoolDashboardDeleteGroupDebugProbe: Equatable {
    let remainingAccountNames: [String]
    let removedTokenAccountNames: [String]
    let selectedGroupName: String
    let missingGroupRemovedTokens: Bool
}

struct PoolDashboardAddAccountDebugProbe: Equatable {
    let addedAccountNames: [String]
    let addedGroupName: String?
    let addedQuota: Int?
    let blankInputWasIgnored: Bool
    let formNameWasReset: Bool
    let formQuotaWasReset: Bool
}

private final class DebugTokenRemovalRecorder {
    private(set) var accountIDs: [UUID] = []

    func append(_ accountID: UUID) {
        accountIDs.append(accountID)
    }
}

private struct DebugProbeAccountPoolStore: AccountPoolStoring {
    let snapshot: AccountPoolSnapshot?
    let tokenByAccountID: [UUID: String]
    var onRemoveToken: (UUID) -> Void = { _ in }

    func load() -> AccountPoolSnapshot? {
        snapshot
    }

    func save(_ snapshot: AccountPoolSnapshot) {}

    func apiToken(for accountID: UUID) -> String? {
        tokenByAccountID[accountID]
    }

    func removeToken(for accountID: UUID) {
        onRemoveToken(accountID)
    }
}

private extension UsageAnalyticsWorkspacePanelView {
    @MainActor
    static func debugConfigured(
        analyticsState: UsageAnalyticsState,
        accounts: [AgentAccount],
        analysisBasisID: String = "usage",
        chartGranularityID: String = "daily",
        accountSortModeID: String = "name",
        selectedAccountKey: String? = nil,
        onClearIdleDelay: @escaping (String?) -> Void = { _ in }
    ) -> UsageAnalyticsWorkspacePanelView {
        var view = UsageAnalyticsWorkspacePanelView(
            analyticsState: analyticsState,
            accounts: accounts,
            onClearIdleDelay: onClearIdleDelay
        )
        view._analysisBasis = State(initialValue: AnalysisBasis(rawValue: analysisBasisID) ?? .usage)
        view._chartGranularity = State(initialValue: ChartGranularity(rawValue: chartGranularityID) ?? .daily)
        view._accountSortMode = State(initialValue: AccountSortMode(rawValue: accountSortModeID) ?? .name)
        view._selectedAccountKey = State(initialValue: selectedAccountKey)
        return view
    }

    @MainActor
    static func debugProbe(
        analyticsState: UsageAnalyticsState,
        accounts: [AgentAccount],
        selectedAccountKey: String?,
        days: Int,
        weeks: Int
    ) -> UsageAnalyticsWorkspaceDebugProbe {
        let allAccountsView = debugConfigured(
            analyticsState: analyticsState,
            accounts: accounts,
            selectedAccountKey: nil
        )
        let selectedAccountView = debugConfigured(
            analyticsState: analyticsState,
            accounts: accounts,
            selectedAccountKey: selectedAccountKey
        )

        let sortModes = AccountSortMode.allCases
        let sortedAccountKeysByMode = Dictionary(uniqueKeysWithValues: sortModes.map { mode in
            let view = debugConfigured(
                analyticsState: analyticsState,
                accounts: accounts,
                accountSortModeID: mode.rawValue,
                selectedAccountKey: nil
            )
            return (mode.rawValue, view.selectableAccountKeys)
        })

        let bases = AnalysisBasis.allCases
        let analysisDescriptions = Dictionary(uniqueKeysWithValues: bases.map { basis in
            let view = debugConfigured(
                analyticsState: analyticsState,
                accounts: accounts,
                analysisBasisID: basis.rawValue,
                selectedAccountKey: selectedAccountKey
            )
            return (basis.rawValue, view.analysisBasisDescriptionText)
        })

        var chartEntryCounts: [String: Int] = [:]
        for basis in bases {
            for granularity in ChartGranularity.allCases {
                let view = debugConfigured(
                    analyticsState: analyticsState,
                    accounts: accounts,
                    analysisBasisID: basis.rawValue,
                    chartGranularityID: granularity.rawValue,
                    selectedAccountKey: selectedAccountKey
                )
                chartEntryCounts["\(basis.rawValue)-\(granularity.rawValue)"] = view.chartEntries.count
            }
        }

        let chartValueLabels = Dictionary(uniqueKeysWithValues: bases.map { basis in
            let view = debugConfigured(
                analyticsState: analyticsState,
                accounts: accounts,
                analysisBasisID: basis.rawValue,
                selectedAccountKey: selectedAccountKey
            )
            return (basis.rawValue, view.chartValueLabel(for: 8))
        })

        let metricSampleDate = Date(timeIntervalSince1970: 0)
        let accountMetricSamples: [String: [Int]] = {
            var samples: [String: [Int]] = [:]

            if let accountKey = accounts.first?.usageAnalyticsAccountKey {
                samples["account"] = metricVector(allAccountsView.accountMetrics(for: accountKey))
            }

            let snapshotKey = "debug-snapshot-only"
            samples["snapshot"] = metricVector(allAccountsView.accountMetrics(
                for: snapshotKey,
                names: [snapshotKey: "Snapshot only"],
                accountsByKey: [:],
                snapshotsByKey: [
                    snapshotKey: UsageAnalyticsAccountSnapshot(
                        accountKey: snapshotKey,
                        lastWeeklyPercent: 150,
                        lastFiveHourPercent: nil,
                        lastWeeklyResetAt: nil,
                        lastFiveHourResetAt: nil,
                        lastSeenAt: metricSampleDate
                    )
                ],
                recordsByKey: [:]
            ))

            let recordKey = "debug-record-only"
            samples["record"] = metricVector(allAccountsView.accountMetrics(
                for: recordKey,
                names: [recordKey: "Record only"],
                accountsByKey: [:],
                snapshotsByKey: [:],
                recordsByKey: [
                    recordKey: UsageAnalyticsRecord(
                        timestamp: metricSampleDate,
                        accountKey: recordKey,
                        weeklyDeltaPercent: 0,
                        fiveHourDeltaPercent: 0,
                        weeklyAbsolutePercent: -25,
                        fiveHourAbsolutePercent: 140,
                        weeklyRemainingPercent: 125,
                        fiveHourRemainingPercent: -4
                    )
                ]
            ))

            let unknownKey = "debug-unknown"
            samples["unknown"] = metricVector(allAccountsView.accountMetrics(
                for: unknownKey,
                names: [unknownKey: "Unknown"],
                accountsByKey: [:],
                snapshotsByKey: [:],
                recordsByKey: [:]
            ))

            return samples
        }()

        var etaValueTexts = selectedAccountView.sortedETAs.map { selectedAccountView.etaValueText($0) }
        etaValueTexts.append(
            selectedAccountView.etaValueText(
                UsageAnalyticsETA(
                    accountKey: "debug-no-eta",
                    remainingPercent: 0,
                    burnPerHour: 0,
                    etaHours: nil
                )
            )
        )
        etaValueTexts.append(
            selectedAccountView.etaValueText(
                UsageAnalyticsETA(
                    accountKey: "debug-sub-hour-eta",
                    remainingPercent: 1,
                    burnPerHour: 4,
                    etaHours: 0.5
                )
            )
        )
        etaValueTexts.append(
            selectedAccountView.etaValueText(
                UsageAnalyticsETA(
                    accountKey: "debug-hour-eta",
                    remainingPercent: 50,
                    burnPerHour: 4,
                    etaHours: 2.4
                )
            )
        )

        return UsageAnalyticsWorkspaceDebugProbe(
            sortedAccountKeysByMode: sortedAccountKeysByMode,
            accountMetricSamples: accountMetricSamples,
            dailyRemainingAll: allAccountsView.dailyRemainingSeries(days: days).map(\.totalWeeklyPercent),
            dailyRemainingSelected: selectedAccountView.dailyRemainingSeries(days: days).map(\.totalWeeklyPercent),
            weeklyRemainingAll: allAccountsView.weeklyRemainingSeries(weeks: weeks).map(\.totalWeeklyPercent),
            weeklyRemainingSelected: selectedAccountView.weeklyRemainingSeries(weeks: weeks).map(\.totalWeeklyPercent),
            dailyWastedAll: allAccountsView.dailyWastedSeries(days: days).map(\.totalWeeklyPercent),
            dailyWastedSelected: selectedAccountView.dailyWastedSeries(days: days).map(\.totalWeeklyPercent),
            weeklyWastedAll: allAccountsView.weeklyWastedSeries(weeks: weeks).map(\.totalWeeklyPercent),
            weeklyWastedSelected: selectedAccountView.weeklyWastedSeries(weeks: weeks).map(\.totalWeeklyPercent),
            dailyIdleDelayAll: allAccountsView.dailyIdleDelaySeries(days: days).map(\.totalWeeklyPercent),
            dailyIdleDelaySelected: selectedAccountView.dailyIdleDelaySeries(days: days).map(\.totalWeeklyPercent),
            weeklyIdleDelayAll: allAccountsView.weeklyIdleDelaySeries(weeks: weeks).map(\.totalWeeklyPercent),
            weeklyIdleDelaySelected: selectedAccountView.weeklyIdleDelaySeries(weeks: weeks).map(\.totalWeeklyPercent),
            analysisDescriptions: analysisDescriptions,
            chartEntryCounts: chartEntryCounts,
            chartValueLabels: chartValueLabels,
            etaValueTexts: etaValueTexts
        )
    }

    private static func metricVector(_ metrics: AccountAnalyticsMetrics) -> [Int] {
        [
            metrics.isPaid ? 1 : 0,
            metrics.weeklyUsage,
            metrics.fiveHourUsage,
            metrics.weeklyRemaining,
            metrics.fiveHourRemaining
        ]
    }

    @MainActor
    static func debugPrivateDetailViews(
        analyticsState: UsageAnalyticsState,
        accounts: [AgentAccount],
        selectedAccountKey: String?
    ) -> some View {
        let view = debugConfigured(
            analyticsState: analyticsState,
            accounts: accounts,
            selectedAccountKey: selectedAccountKey
        )

        return VStack(alignment: .leading, spacing: 8) {
            view.operationsView
            view.thresholdAndAnomalyView
            view.etaView
        }
    }

    @MainActor
    static func debugPrivateCoverageViews(
        analyticsState: UsageAnalyticsState,
        accounts: [AgentAccount],
        selectedAccountKey: String?
    ) -> some View {
        let view = debugConfigured(
            analyticsState: analyticsState,
            accounts: accounts,
            selectedAccountKey: selectedAccountKey
        )

        return VStack(alignment: .leading, spacing: 8) {
            view.coverageAndSwitchView
            view.recommendationView
        }
    }
}

extension PoolDashboardView {
    static func debugWorkspaceDrawerStateSnapshots() -> [(isVisible: Bool, symbolName: String, actionTitleKey: String, nextSymbolName: String)] {
        [WorkspaceDrawerState.collapsed, .partial, .expanded].map { state in
            (
                isVisible: state.isVisible,
                symbolName: state.symbolName,
                actionTitleKey: state.actionTitleKey,
                nextSymbolName: state.next().symbolName
            )
        }
    }

    static func debugSpecialResetKinds() -> [(rawValue: String, interval: TimeInterval, title: String)] {
        [SpecialResetKind.weekly, .fiveHour].map { kind in
            (rawValue: kind.rawValue, interval: kind.interval, title: kind.title)
        }
    }

    static func debugSpecialResetRecordID(accountKey: String = "account:test", accountName: String = "Test") -> String {
        SpecialResetRecord(accountKey: accountKey, accountName: accountName).id
    }

    @MainActor
    static func debugSpecialResetPresentationProbe(
        accountName: String,
        accountWeeklyResetAt: Date,
        accountFiveHourResetAt: Date,
        fallbackWeeklyResetAt: Date,
        fallbackFiveHourResetAt: Date,
        eventWeeklyObservedAt: Date,
        eventFiveHourObservedAt: Date,
        detectedAt: Date
    ) -> SpecialResetPresentationDebugProbe {
        let account = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D5")!,
            name: accountName,
            usedUnits: 10,
            quota: 100,
            usageWindowResetAt: fallbackWeeklyResetAt,
            primaryUsagePercent: 40,
            primaryUsageResetAt: accountFiveHourResetAt,
            secondaryUsagePercent: 20,
            secondaryUsageResetAt: accountWeeklyResetAt,
            isPaid: true
        )
        var view = PoolDashboardView(store: debugTransientStore())
        view._state = State(initialValue: AccountPoolState(accounts: [account], mode: .manual))

        let accountKey = view.specialResetWatchAccountKey(for: account)
        let accountRecord = SpecialResetRecord(
            accountKey: accountKey,
            accountName: account.name,
            expectedWeeklyResetAt: fallbackWeeklyResetAt,
            expectedFiveHourResetAt: fallbackFiveHourResetAt
        )
        let fallbackRecord = SpecialResetRecord(
            accountKey: "debug:fallback",
            accountName: "Fallback",
            expectedWeeklyResetAt: fallbackWeeklyResetAt,
            expectedFiveHourResetAt: fallbackFiveHourResetAt
        )
        let unavailableRecord = SpecialResetRecord(
            accountKey: "debug:unavailable",
            accountName: "Unavailable"
        )
        let accountDates = view.specialResetDisplayedResetDates(for: accountRecord)
        let fallbackDates = view.specialResetDisplayedResetDates(for: fallbackRecord)
        let unavailableDates = view.specialResetDisplayedResetDates(for: unavailableRecord)
        let event = SpecialResetEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E5")!,
            detectedAt: detectedAt,
            accountKey: accountKey,
            accountName: view.normalizedSpecialResetAccountName(account),
            previousWeeklyExpectedAt: accountWeeklyResetAt,
            observedWeeklyNextResetAt: eventWeeklyObservedAt,
            previousFiveHourExpectedAt: accountFiveHourResetAt,
            observedFiveHourNextResetAt: eventFiveHourObservedAt
        )
        let eventDateTexts = [
            accountWeeklyResetAt,
            eventWeeklyObservedAt,
            accountFiveHourResetAt,
            eventFiveHourObservedAt,
            detectedAt
        ].map { view.specialResetDateText($0) }

        return SpecialResetPresentationDebugProbe(
            accountRecordWeeklyText: accountDates.weekly,
            accountRecordFiveHourText: accountDates.fiveHour,
            fallbackRecordWeeklyText: fallbackDates.weekly,
            fallbackRecordFiveHourText: fallbackDates.fiveHour,
            unavailableWeeklyText: unavailableDates.weekly,
            unavailableFiveHourText: unavailableDates.fiveHour,
            eventMessage: view.specialResetEventMessage(for: event),
            eventDateTexts: eventDateTexts
        )
    }

    @MainActor
    static func debugSpecialResetBaselineProbe(
        accounts: [AgentAccount],
        now: Date
    ) -> SpecialResetBaselineDebugProbe {
        let view = PoolDashboardView(store: debugTransientStore())
        let baselineState = view.specialResetBaselineWatchState(accounts: accounts, now: now)
        return SpecialResetBaselineDebugProbe(
            recordNames: baselineState.records.map(\.accountName),
            expectedWeeklyResetAts: baselineState.records.map(\.expectedWeeklyResetAt),
            expectedFiveHourResetAts: baselineState.records.map(\.expectedFiveHourResetAt),
            lastSeenWeeklyUsagePercents: baselineState.records.map(\.lastSeenWeeklyUsagePercent),
            lastSeenFiveHourUsagePercents: baselineState.records.map(\.lastSeenFiveHourUsagePercent),
            lastSeenAts: baselineState.records.map(\.lastSeenAt),
            eventCount: baselineState.events.count,
            lastEvaluatedAt: baselineState.lastEvaluatedAt
        )
    }

    @MainActor
    static func debugSpecialResetEvaluationProbe(
        accounts: [AgentAccount],
        existingAccountKey: String,
        staleAccountKey: String,
        previousWeeklyExpectedAt: Date,
        previousFiveHourExpectedAt: Date,
        now: Date
    ) -> SpecialResetEvaluationDebugProbe {
        let view = PoolDashboardView(store: debugTransientStore())
        var watchState = SpecialResetWatchState()
        watchState.records = [
            SpecialResetRecord(
                accountKey: existingAccountKey,
                accountName: "Old Name",
                expectedWeeklyResetAt: previousWeeklyExpectedAt,
                expectedFiveHourResetAt: previousFiveHourExpectedAt,
                lastObservedWeeklyResetAt: previousWeeklyExpectedAt,
                lastObservedFiveHourResetAt: previousFiveHourExpectedAt,
                lastSeenWeeklyUsagePercent: 82,
                lastSeenUsedUnits: 82,
                lastSeenFiveHourUsagePercent: 74,
                lastSeenAt: now.addingTimeInterval(-3_600)
            ),
            SpecialResetRecord(
                accountKey: staleAccountKey,
                accountName: "Stale",
                expectedWeeklyResetAt: previousWeeklyExpectedAt,
                expectedFiveHourResetAt: previousFiveHourExpectedAt,
                lastSeenWeeklyUsagePercent: 50,
                lastSeenFiveHourUsagePercent: 50,
                lastSeenAt: now.addingTimeInterval(-3_600)
            )
        ]

        guard let output = view.specialResetEvaluationOutput(
            currentState: watchState,
            accounts: accounts,
            now: now,
            graceMinutes: 1,
            notificationsEnabled: true
        ) else {
            return SpecialResetEvaluationDebugProbe(
                recordNames: [],
                eventAccountNames: [],
                prunedStaleRecord: false,
                shouldNotify: false,
                lastNotificationAt: nil,
                lastEvaluatedAt: nil
            )
        }

        return SpecialResetEvaluationDebugProbe(
            recordNames: output.state.records.map(\.accountName),
            eventAccountNames: output.state.events.map(\.accountName),
            prunedStaleRecord: !output.state.records.contains(where: { $0.accountKey == staleAccountKey }),
            shouldNotify: output.shouldNotify,
            lastNotificationAt: output.state.lastNotificationAt,
            lastEvaluatedAt: output.state.lastEvaluatedAt
        )
    }

    @MainActor
    static func debugSpecialResetNotificationRequestProbe() -> SpecialResetNotificationRequestDebugProbe {
        let view = PoolDashboardView(store: debugTransientStore())
        let previousWeekly = Date(timeIntervalSince1970: 1_800_100_000)
        let observedWeekly = Date(timeIntervalSince1970: 1_800_700_000)
        let previousFiveHour = Date(timeIntervalSince1970: 1_800_010_000)
        let observedFiveHour = Date(timeIntervalSince1970: 1_800_030_000)
        let detection = SpecialResetDetection(
            accountKey: "debug:account",
            accountName: "Reset Debug",
            previousWeeklyExpectedAt: previousWeekly,
            observedWeeklyNextResetAt: observedWeekly,
            previousFiveHourExpectedAt: previousFiveHour,
            observedFiveHourNextResetAt: observedFiveHour,
            detectedAt: Date(timeIntervalSince1970: 1_800_040_000)
        )
        let emptyRequest = view.specialResetDetectionNotificationRequest([])
        let request = view.specialResetDetectionNotificationRequest([detection])
        let observedDateTexts = [
            view.specialResetDateText(observedWeekly),
            view.specialResetDateText(observedFiveHour)
        ]

        return SpecialResetNotificationRequestDebugProbe(
            emptyRequestIsNil: emptyRequest == nil,
            requestKey: request?.key,
            requestTitle: request?.title ?? "",
            requestBodyContainsAccountName: request?.body.contains(detection.accountName) == true,
            requestBodyContainsObservedDates: observedDateTexts.allSatisfy { request?.body.contains($0) == true },
            requestMinInterval: request?.minInterval
        )
    }

    @MainActor
    static func debugNormalizeStoredUsageAnalyticsProbe(
        rawState: String,
        accounts: [AgentAccount],
        maxStoredRecords: Int,
        now: Date
    ) -> UsageAnalyticsStorageNormalizationDebugProbe {
        let output = normalizedStoredUsageAnalyticsPayload(
            rawValue: rawState,
            accounts: accounts,
            maxStoredRecords: maxStoredRecords,
            now: now
        )
        let storedRawValue = output?.rewrittenRawValue ?? rawState
        let storedState = storedRawValue
            .data(using: .utf8)
            .flatMap { try? JSONDecoder().decode(UsageAnalyticsState.self, from: $0) }
        let invalidRawReturnedNil = normalizedStoredUsageAnalyticsPayload(
            rawValue: "{",
            accounts: accounts,
            maxStoredRecords: maxStoredRecords,
            now: now
        ) == nil

        return UsageAnalyticsStorageNormalizationDebugProbe(
            didRewriteRawState: output?.rewrittenRawValue != nil,
            storedRecordKeys: storedState?.records.map(\.accountKey) ?? [],
            loadedRecordKeys: output?.normalizedState.records.map(\.accountKey) ?? [],
            invalidRawReturnedNil: invalidRawReturnedNil
        )
    }

    @MainActor
    static func debugUsageAnalyticsStorageLifecycleProbe() throws -> UsageAnalyticsStorageLifecycleDebugProbe {
        let defaults = UserDefaults.standard
        let rawBackup = defaults.object(forKey: usageAnalyticsStateKey)
        let maxRecordsBackup = defaults.object(forKey: usageAnalyticsMaxStoredRecordsKey)
        defer {
            if let rawBackup {
                defaults.set(rawBackup, forKey: usageAnalyticsStateKey)
            } else {
                defaults.removeObject(forKey: usageAnalyticsStateKey)
            }
            if let maxRecordsBackup {
                defaults.set(maxRecordsBackup, forKey: usageAnalyticsMaxStoredRecordsKey)
            } else {
                defaults.removeObject(forKey: usageAnalyticsMaxStoredRecordsKey)
            }
        }

        let now = Date()
        let recent = UsageAnalyticsRecord(
            timestamp: now,
            accountKey: "recent",
            weeklyDeltaPercent: 10,
            fiveHourDeltaPercent: 2
        )
        let expired = UsageAnalyticsRecord(
            timestamp: now.addingTimeInterval(-200 * 24 * 3_600),
            accountKey: "expired",
            weeklyDeltaPercent: 90,
            fiveHourDeltaPercent: 70
        )
        let rawState = UsageAnalyticsState(records: [expired, recent], snapshots: [], lastUpdatedAt: now)
        let rawData = try JSONEncoder().encode(rawState)
        let rawText = String(data: rawData, encoding: .utf8) ?? ""

        let emptyView = PoolDashboardView(store: debugTransientStore())
        emptyView.usageAnalyticsStateRaw = ""
        emptyView.loadUsageAnalyticsStateFromStorage()

        let loadOutput = normalizedStoredUsageAnalyticsPayload(
            rawValue: rawText,
            accounts: [],
            maxStoredRecords: UsageAnalyticsEngine.defaultMaxStoredRecords,
            now: now
        )

        let loadView = PoolDashboardView(store: debugTransientStore())
        loadView.usageAnalyticsStateRaw = rawText
        loadView.usageAnalyticsMaxStoredRecords = UsageAnalyticsEngine.defaultMaxStoredRecords
        loadView.loadUsageAnalyticsStateFromStorage()

        var normalizeView = PoolDashboardView(store: debugTransientStore())
        normalizeView.usageAnalyticsStateRaw = rawText
        normalizeView.usageAnalyticsMaxStoredRecords = UsageAnalyticsEngine.defaultMaxStoredRecords
        normalizeView._usageAnalyticsStateLoaded = State(initialValue: true)
        normalizeView.normalizeStoredUsageAnalyticsForCurrentLimit()

        let normalizedRawRecordKeys: [String]
        if let rewrittenRawValue = loadOutput?.rewrittenRawValue,
           let data = rewrittenRawValue.data(using: .utf8),
           let decodedState = try? JSONDecoder().decode(UsageAnalyticsState.self, from: data) {
            normalizedRawRecordKeys = decodedState.records.map(\.accountKey)
        } else {
            normalizedRawRecordKeys = []
        }

        return UsageAnalyticsStorageLifecycleDebugProbe(
            emptyLoadMarkedLoaded: true,
            emptyLoadRecordCount: 0,
            loadedRecordKeys: loadOutput?.normalizedState.records.map(\.accountKey) ?? [],
            loadedStateWasPersisted: loadOutput?.rewrittenRawValue != nil,
            normalizedLoadedRecordKeys: loadOutput?.normalizedState.records.map(\.accountKey) ?? [],
            normalizedRawRecordKeys: normalizedRawRecordKeys
        )
    }

    @MainActor
    static func debugUsageAnalyticsSyncLifecycleProbe() throws -> UsageAnalyticsSyncLifecycleDebugProbe {
        let defaults = UserDefaults.standard
        let rawBackup = defaults.object(forKey: usageAnalyticsStateKey)
        let maxRecordsBackup = defaults.object(forKey: usageAnalyticsMaxStoredRecordsKey)
        defer {
            if let rawBackup {
                defaults.set(rawBackup, forKey: usageAnalyticsStateKey)
            } else {
                defaults.removeObject(forKey: usageAnalyticsStateKey)
            }
            if let maxRecordsBackup {
                defaults.set(maxRecordsBackup, forKey: usageAnalyticsMaxStoredRecordsKey)
            } else {
                defaults.removeObject(forKey: usageAnalyticsMaxStoredRecordsKey)
            }
        }

        let accountID = UUID(uuidString: "00000000-0000-0000-0000-00000000DA71")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let baseAccount = AgentAccount(
            id: accountID,
            name: "analytics-sync@example.com",
            usedUnits: 10,
            quota: 100,
            chatGPTAccountID: "acct-analytics-sync",
            usageWindowResetAt: now.addingTimeInterval(7 * 24 * 3_600),
            primaryUsagePercent: 20,
            primaryUsageResetAt: now.addingTimeInterval(5 * 3_600),
            isPaid: true
        )
        let updatedAccount = AgentAccount(
            id: accountID,
            name: "analytics-sync@example.com",
            usedUnits: 35,
            quota: 100,
            chatGPTAccountID: "acct-analytics-sync",
            usageWindowResetAt: now.addingTimeInterval(7 * 24 * 3_600),
            primaryUsagePercent: 55,
            primaryUsageResetAt: now.addingTimeInterval(5 * 3_600),
            isPaid: true
        )
        let expectedAccountKey = baseAccount.usageAnalyticsAccountKey

        func poolState(for account: AgentAccount) -> AccountPoolState {
            var state = AccountPoolState(accounts: [account], mode: .manual)
            state.markActiveAccountForSwitchLaunch(accountID, now: now)
            return state
        }

        func configuredView(
            account: AgentAccount,
            analyticsState: UsageAnalyticsState? = nil,
            loaded: Bool,
            workspace: Workspace = .authentication
        ) -> PoolDashboardView {
            var view = PoolDashboardView(store: debugTransientStore())
            view._state = State(initialValue: poolState(for: account))
            view._usageAnalyticsState = State(initialValue: analyticsState ?? UsageAnalyticsState())
            view._usageAnalyticsStateLoaded = State(initialValue: loaded)
            view._selectedWorkspace = State(initialValue: workspace)
            return view
        }

        let unloadedSeedView = configuredView(account: baseAccount, loaded: false)
        let unloadedSeedDidRun = unloadedSeedView.seedUsageAnalyticsIfNeeded(now: now)

        let seedView = configuredView(account: baseAccount, loaded: true)
        let seedDidRun = seedView.seedUsageAnalyticsIfNeeded(now: now)

        let alreadySeededState = UsageAnalyticsState(
            records: [],
            snapshots: [
                UsageAnalyticsAccountSnapshot(
                    accountKey: "preseeded",
                    lastWeeklyPercent: 1,
                    lastFiveHourPercent: 1,
                    lastSeenAt: now
                )
            ],
            lastUpdatedAt: now
        )
        let alreadySeededView = configuredView(
            account: baseAccount,
            analyticsState: alreadySeededState,
            loaded: true
        )
        let alreadySeededDidRun = alreadySeededView.seedUsageAnalyticsIfNeeded(now: now)

        let unloadedNonAnalyticsUpdateView = configuredView(account: updatedAccount, loaded: false)
        let unloadedNonAnalyticsUpdateDidRun = unloadedNonAnalyticsUpdateView.updateUsageAnalyticsAfterSync(
            now: now.addingTimeInterval(3_600)
        )

        let seededState = UsageAnalyticsEngine.seed(
            state: UsageAnalyticsState(),
            accounts: [baseAccount],
            activeAccountKey: expectedAccountKey,
            now: now
        )
        let seededData = try JSONEncoder().encode(seededState)
        let seededRawValue = String(data: seededData, encoding: .utf8) ?? ""
        let workspaceTriggeredView = configuredView(
            account: updatedAccount,
            loaded: false,
            workspace: .usageAnalytics
        )
        workspaceTriggeredView.usageAnalyticsStateRaw = seededRawValue
        workspaceTriggeredView.usageAnalyticsMaxStoredRecords = UsageAnalyticsEngine.defaultMaxStoredRecords
        let workspaceTriggeredUpdateDidRun = workspaceTriggeredView.updateUsageAnalyticsAfterSync(
            now: now.addingTimeInterval(3_600)
        )

        let loadedUpdateView = configuredView(
            account: updatedAccount,
            analyticsState: seededState,
            loaded: true
        )
        let loadedUpdateDidRun = loadedUpdateView.updateUsageAnalyticsAfterSync(now: now.addingTimeInterval(3_600))
        let expectedUpdatedState = UsageAnalyticsEngine.update(
            state: seededState,
            accounts: [updatedAccount],
            activeAccountKey: expectedAccountKey,
            now: now.addingTimeInterval(3_600),
            maxStoredRecords: UsageAnalyticsEngine.defaultMaxStoredRecords
        )

        return UsageAnalyticsSyncLifecycleDebugProbe(
            expectedAccountKey: expectedAccountKey,
            unloadedSeedSnapshotCount: unloadedSeedDidRun ? -1 : 0,
            seededSnapshotCount: seedDidRun ? seededState.snapshots.count : 0,
            seededActiveAccountKey: seedDidRun ? seededState.lastActiveAccountKey : nil,
            alreadySeededSnapshotCount: alreadySeededDidRun ? 0 : alreadySeededState.snapshots.count,
            unloadedNonAnalyticsUpdateRecordCount: unloadedNonAnalyticsUpdateDidRun ? -1 : 0,
            unloadedNonAnalyticsMarkedLoaded: unloadedNonAnalyticsUpdateDidRun,
            workspaceTriggeredUpdateLoadedState: workspaceTriggeredUpdateDidRun,
            loadedUpdateRecordCount: loadedUpdateDidRun ? expectedUpdatedState.records.count : 0,
            loadedUpdateLastActiveAccountKey: loadedUpdateDidRun ? expectedUpdatedState.lastActiveAccountKey : nil
        )
    }

    @MainActor
    static func debugManualOAuthPreparationProbe() -> ManualOAuthPreparationDebugProbe {
        let defaults = UserDefaults.standard
        let storageKeys = [
            "oauth_issuer",
            "oauth_client_id",
            "oauth_scopes",
            "oauth_redirect_uri",
            "oauth_originator",
            "oauth_workspace_id"
        ]
        let defaultsBackup = Dictionary(uniqueKeysWithValues: storageKeys.map { key in
            (key, defaults.object(forKey: key))
        })
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        let pasteboardStringBackup = pasteboard.string(forType: .string)
        #endif
        defer {
            for key in storageKeys {
                if let value = defaultsBackup[key] ?? nil {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            #if canImport(AppKit)
            pasteboard.clearContents()
            if let pasteboardStringBackup {
                pasteboard.setString(pasteboardStringBackup, forType: .string)
            }
            #endif
        }

        let flowCoordinator = PoolDashboardOAuthSignInFlowCoordinator()
        let validInput = PoolDashboardOAuthSignInFlowCoordinator.Input(
            issuer: "https://auth.openai.com",
            clientID: Self.defaultOAuthClientID,
            scopes: OAuthClientConfiguration.defaultScopes,
            redirectURI: OAuthClientConfiguration.defaultRedirectURI,
            originator: OAuthClientConfiguration.defaultOriginator,
            workspaceID: "",
            fallbackQuota: PoolDashboardFormState.defaultQuota
        )
        let invalidInput = PoolDashboardOAuthSignInFlowCoordinator.Input(
            issuer: "not-valid-url",
            clientID: "",
            scopes: "openid",
            redirectURI: "http://localhost:1455/auth/callback",
            originator: OAuthClientConfiguration.defaultOriginator,
            workspaceID: "",
            fallbackQuota: 100
        )

        let successOutput = flowCoordinator.prepareManualOAuthSignIn(input: validInput)
        let successView = PoolDashboardView(store: debugTransientStore())
        successView.oauthIssuer = validInput.issuer
        successView.oauthClientID = validInput.clientID
        successView.oauthScopes = validInput.scopes
        successView.oauthRedirectURI = validInput.redirectURI
        successView.oauthOriginator = validInput.originator
        successView.oauthWorkspaceID = validInput.workspaceID
        successView.prepareManualOAuthSignIn()

        let failureOutput = flowCoordinator.prepareManualOAuthSignIn(input: invalidInput)
        let failureView = PoolDashboardView(store: debugTransientStore())
        failureView.oauthIssuer = invalidInput.issuer
        failureView.oauthClientID = invalidInput.clientID
        failureView.oauthScopes = invalidInput.scopes
        failureView.oauthRedirectURI = invalidInput.redirectURI
        failureView.oauthOriginator = invalidInput.originator
        failureView.oauthWorkspaceID = invalidInput.workspaceID
        failureView.prepareManualOAuthSignIn()

        return ManualOAuthPreparationDebugProbe(
            successPendingContextWasStored: successOutput.authorizationURL != nil
                && successOutput.expectedState?.isEmpty == false
                && successOutput.codeVerifier?.isEmpty == false,
            successURLContainsAuthorizePath: successOutput.authorizationURL?
                .absoluteString
                .contains("/oauth/authorize") == true,
            successMessage: successOutput.oauthError == nil ? L10n.text("oauth.manual.copy_success") : nil,
            successErrorWasCleared: successOutput.oauthError == nil,
            failurePendingContextIsNil: failureOutput.authorizationURL == nil
                && failureOutput.expectedState == nil
                && failureOutput.codeVerifier == nil,
            failureErrorIsNotEmpty: !(failureOutput.oauthError ?? "").isEmpty,
            failureSuccessMessageIsNil: failureOutput.oauthError != nil
        )
    }

    @MainActor
    static func debugOAuthSignInProbe() async -> OAuthSignInDebugProbe {
        let defaults = UserDefaults.standard
        let storageKeys = [
            "oauth_issuer",
            "oauth_client_id",
            "oauth_scopes",
            "oauth_redirect_uri",
            "oauth_originator",
            "oauth_workspace_id"
        ]
        let defaultsBackup = Dictionary(uniqueKeysWithValues: storageKeys.map { key in
            (key, defaults.object(forKey: key))
        })
        defer {
            for key in storageKeys {
                if let value = defaultsBackup[key] ?? nil {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        let invalidInput = PoolDashboardOAuthSignInFlowCoordinator.Input(
            issuer: "not-valid-url",
            clientID: "",
            scopes: "openid",
            redirectURI: "http://localhost:1455/auth/callback",
            originator: OAuthClientConfiguration.defaultOriginator,
            workspaceID: "",
            fallbackQuota: PoolDashboardFormState.defaultQuota
        )

        var signInView = PoolDashboardView(store: debugTransientStore())
        signInView.oauthIssuer = invalidInput.issuer
        signInView.oauthClientID = invalidInput.clientID
        signInView.oauthScopes = invalidInput.scopes
        signInView.oauthRedirectURI = invalidInput.redirectURI
        signInView.oauthOriginator = invalidInput.originator
        signInView.oauthWorkspaceID = invalidInput.workspaceID
        signInView._state = State(initialValue: AccountPoolState(accounts: [], mode: .manual))
        signInView._formState = State(initialValue: PoolDashboardFormState())
        signInView._viewState = State(initialValue: PoolDashboardViewState())
        await signInView.signInWithOAuth()

        let flowCoordinator = PoolDashboardOAuthSignInFlowCoordinator()
        let invalidOutput = await flowCoordinator.signInWithOAuth(
            from: AccountPoolState(accounts: [], mode: .manual),
            viewState: PoolDashboardViewState(),
            oauthAccountName: "",
            input: invalidInput
        )

        return OAuthSignInDebugProbe(
            invalidConfigurationErrorIsNotEmpty: !(invalidOutput.viewState.oauthError ?? "").isEmpty,
            invalidConfigurationSuccessMessageIsNil: invalidOutput.viewState.oauthSuccessMessage == nil,
            invalidConfigurationShouldRefreshLocalAccounts: invalidOutput.shouldRefreshLocalOAuthAccounts
        )
    }

    @MainActor
    static func debugManualOAuthCallbackProbe() async -> ManualOAuthCallbackDebugProbe {
        let defaults = UserDefaults.standard
        let storageKeys = [
            "oauth_issuer",
            "oauth_client_id",
            "oauth_scopes",
            "oauth_redirect_uri",
            "oauth_originator",
            "oauth_workspace_id"
        ]
        let defaultsBackup = Dictionary(uniqueKeysWithValues: storageKeys.map { key in
            (key, defaults.object(forKey: key))
        })
        defer {
            for key in storageKeys {
                if let value = defaultsBackup[key] ?? nil {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        let validInput = PoolDashboardOAuthSignInFlowCoordinator.Input(
            issuer: "https://auth.openai.com",
            clientID: Self.defaultOAuthClientID,
            scopes: OAuthClientConfiguration.defaultScopes,
            redirectURI: OAuthClientConfiguration.defaultRedirectURI,
            originator: OAuthClientConfiguration.defaultOriginator,
            workspaceID: "",
            fallbackQuota: PoolDashboardFormState.defaultQuota
        )

        let missingContextView = PoolDashboardView(store: debugTransientStore())
        await missingContextView.importManualOAuthCallback()

        var invalidCallbackView = PoolDashboardView(store: debugTransientStore())
        invalidCallbackView.oauthIssuer = validInput.issuer
        invalidCallbackView.oauthClientID = validInput.clientID
        invalidCallbackView.oauthScopes = validInput.scopes
        invalidCallbackView.oauthRedirectURI = validInput.redirectURI
        invalidCallbackView.oauthOriginator = validInput.originator
        invalidCallbackView.oauthWorkspaceID = validInput.workspaceID
        invalidCallbackView._state = State(initialValue: AccountPoolState(accounts: [], mode: .manual))
        invalidCallbackView._formState = State(initialValue: PoolDashboardFormState())
        invalidCallbackView._viewState = State(initialValue: PoolDashboardViewState())
        invalidCallbackView._manualOAuthCallbackURL = State(initialValue: "   ")
        invalidCallbackView._pendingManualOAuthContext = State(initialValue: PendingManualOAuthContext(
            expectedState: "expected-state",
            codeVerifier: "code-verifier",
            authorizationURL: URL(string: "https://auth.openai.com/oauth/authorize")!
        ))
        await invalidCallbackView.importManualOAuthCallback()

        let flowCoordinator = PoolDashboardOAuthSignInFlowCoordinator()
        let invalidOutput = await flowCoordinator.importManualOAuthCallback(
            from: AccountPoolState(accounts: [], mode: .manual),
            viewState: PoolDashboardViewState(),
            oauthAccountName: "",
            input: validInput,
            callbackURLString: "   ",
            expectedState: "expected-state",
            codeVerifier: "code-verifier"
        )

        return ManualOAuthCallbackDebugProbe(
            missingContextError: L10n.text("oauth.error.invalid_callback"),
            missingContextSuccessMessageIsNil: true,
            invalidCallbackErrorIsNotEmpty: !(invalidOutput.viewState.oauthError ?? "").isEmpty,
            invalidCallbackSuccessMessageIsNil: invalidOutput.viewState.oauthSuccessMessage == nil,
            invalidCallbackShouldRefreshLocalAccounts: invalidOutput.shouldRefreshLocalOAuthAccounts
        )
    }

    @MainActor
    static func debugRelayAccountAdditionProbe() async -> RelayAccountAdditionDebugProbe {
        let initialState = AccountPoolState(accounts: [], mode: .manual)
        let relayName = "Coverage Relay"
        let providerID = "coverage_relay"
        let providerName = "Coverage Relay Provider"
        let baseURL = "https://relay.example.com/v1"
        let wireAPI = AgentAccount.defaultRelayWireAPI
        let apiKey = " sk-coverage-relay "

        let coordinator = PoolDashboardRelayAccountCoordinator()
        let output = await coordinator.addRelayAccount(
            to: initialState,
            viewState: PoolDashboardViewState(),
            name: relayName,
            providerID: providerID,
            providerName: providerName,
            baseURL: baseURL,
            wireAPI: wireAPI,
            apiKey: apiKey
        )

        var form = PoolDashboardFormState()
        form.relayAccountName = relayName
        form.relayProviderID = providerID
        form.relayProviderName = providerName
        form.relayBaseURL = baseURL
        form.relayWireAPI = wireAPI
        form.relayAPIKey = apiKey

        var view = PoolDashboardView(store: debugTransientStore())
        view._state = State(initialValue: initialState)
        view._viewState = State(initialValue: PoolDashboardViewState())
        view._formState = State(initialValue: form)
        await view.performAddRelayAccount()

        let addedAccount = output.state.accounts.first
        return RelayAccountAdditionDebugProbe(
            addedAccountCount: output.state.accounts.count,
            addedAccountIsRelay: addedAccount?.isRelayAPIKeyAccount == true,
            relayUsageSyncUnavailable: addedAccount?.usageSyncError == AgentAccount.relayUsageSyncUnavailableReason,
            successMessage: output.viewState.relaySuccessMessage,
            errorWasCleared: output.viewState.relayError == nil
        )
    }

    @MainActor
    static func debugLocalOAuthImportProbe() async -> LocalOAuthImportDebugProbe {
        let localAccount = LocalCodexOAuthAccount(
            id: "missing-account-id",
            displayName: "Missing Account ID",
            email: nil,
            source: "~/.codex/auth.json",
            accessToken: "sk-local-missing-account-id",
            refreshToken: "refresh-local",
            idToken: "id-local",
            chatGPTAccountID: nil
        )
        let initialState = AccountPoolState(accounts: [], mode: .manual)
        let initialViewModel = LocalOAuthImportViewModel(accounts: [localAccount])

        var view = PoolDashboardView(store: debugTransientStore())
        view._state = State(initialValue: initialState)
        view._viewState = State(initialValue: PoolDashboardViewState())
        view._localOAuthImportViewModel = State(initialValue: initialViewModel)
        await view.importLocalOAuthAccount(localAccount)

        let output = await PoolDashboardLocalImportFlowCoordinator().importLocalOAuthAccount(
            localAccount,
            from: initialState,
            viewModel: initialViewModel,
            viewState: PoolDashboardViewState(),
            onRawResponse: { _ in }
        )

        return LocalOAuthImportDebugProbe(
            didImportMissingAccountID: output.didImport,
            accountCountAfterMissingAccountID: output.state.accounts.count,
            errorMessage: output.viewModel.errorMessage,
            successMessageIsNil: output.viewModel.successMessage == nil
        )
    }

    @MainActor
    static func debugViewMutationWrapperProbe() -> ViewMutationWrapperDebugProbe {
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F6")!
        let account = AgentAccount(
            id: accountID,
            name: "OAuth",
            usedUnits: 0,
            quota: 100
        )
        let initialState = AccountPoolState(accounts: [], mode: .manual)
        var nextState = AccountPoolState(accounts: [account], mode: .manual)
        nextState.evaluate()

        var view = PoolDashboardView(store: debugTransientStore())
        view._state = State(initialValue: initialState)
        view._formState = State(initialValue: {
            var form = PoolDashboardFormState()
            form.oauthAccountName = "oauth-before"
            return form
        }())
        view._viewState = State(initialValue: PoolDashboardViewState())
        view._localOAuthImportViewModel = State(initialValue: LocalOAuthImportViewModel())
        view._sessionAuthorizedAuthFileURL = State(initialValue: nil)

        var oauthViewState = PoolDashboardViewState()
        oauthViewState.oauthSuccessMessage = "oauth-ok"
        view.applyOAuthSignInOutput(
            PoolDashboardOAuthSignInFlowCoordinator.Output(
                state: nextState,
                viewState: oauthViewState,
                oauthAccountName: "oauth-next",
                shouldRefreshLocalOAuthAccounts: false
            )
        )

        var localImportViewState = PoolDashboardViewState()
        localImportViewState.syncError = "import-error"
        view.applyLocalImportOutput(
            PoolDashboardLocalImportFlowCoordinator.Output(
                state: nextState,
                viewModel: LocalOAuthImportViewModel(),
                viewState: localImportViewState,
                didImport: false
            )
        )

        let pickedAuthFileURL = URL(fileURLWithPath: "/tmp/auth.json")
        _ = view.applyAndReturnPickedAuthFileURL(
            PoolDashboardLocalAccountsFlowCoordinator.Output(
                state: nextState,
                viewModel: LocalOAuthImportViewModel(),
                sessionAuthorizedAuthFileURL: pickedAuthFileURL,
                pickedAuthFileURL: pickedAuthFileURL
            )
        )

        let switchSessionURL = URL(fileURLWithPath: "/tmp/switch-auth.json")
        var switchViewState = PoolDashboardViewState()
        switchViewState.lastSwitchLaunchLog = "switch-log"
        view.applySwitchLaunchOutput(
            PoolDashboardSwitchLaunchFlowCoordinator.Output(
                viewModel: LocalOAuthImportViewModel(),
                viewState: switchViewState,
                sessionAuthorizedAuthFileURL: switchSessionURL,
                didSwitchAuth: false
            )
        )

        return ViewMutationWrapperDebugProbe(
            oauthAccountName: "oauth-next",
            oauthSuccessMessage: oauthViewState.oauthSuccessMessage,
            localImportError: localImportViewState.syncError,
            pickedAuthFileURLPath: pickedAuthFileURL.path,
            switchLaunchLog: switchViewState.lastSwitchLaunchLog,
            switchSessionURLPath: switchSessionURL.path
        )
    }

    @MainActor
    static func debugAutomaticSwitchDecisionProbe() -> AutomaticSwitchDecisionDebugProbe {
        let currentID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!
        let previousID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F2")!
        let current = AgentAccount(
            id: currentID,
            name: "Current",
            usedUnits: 12,
            quota: 100,
            chatGPTAccountID: "current",
            isPaid: true
        )
        let previous = AgentAccount(
            id: previousID,
            name: "Previous",
            usedUnits: 34,
            quota: 100,
            chatGPTAccountID: "previous",
            isPaid: true
        )

        func output(didSwitchAuth: Bool, error: String? = nil) -> PoolDashboardSwitchLaunchFlowCoordinator.Output {
            var viewState = PoolDashboardViewState()
            viewState.switchLaunchError = error
            return PoolDashboardSwitchLaunchFlowCoordinator.Output(
                viewModel: LocalOAuthImportViewModel(),
                viewState: viewState,
                sessionAuthorizedAuthFileURL: nil,
                didSwitchAuth: didSwitchAuth
            )
        }

        var view = PoolDashboardView(store: debugTransientStore())
        view._state = State(initialValue: AccountPoolState(accounts: [previous, current], mode: .intelligent))
        let success = view.automaticSwitchDecision(
            account: current,
            previousActiveAccountID: previousID,
            output: output(didSwitchAuth: true)
        )
        let failure = view.automaticSwitchDecision(
            account: current,
            previousActiveAccountID: previousID,
            output: output(didSwitchAuth: false, error: " Boom ")
        )

        var missingPreviousView = PoolDashboardView(store: debugTransientStore())
        missingPreviousView._state = State(initialValue: AccountPoolState(accounts: [current], mode: .intelligent))
        let missingPrevious = missingPreviousView.automaticSwitchDecision(
            account: current,
            previousActiveAccountID: previousID,
            output: output(didSwitchAuth: false, error: "Boom")
        )

        return AutomaticSwitchDecisionDebugProbe(
            successMarkedCurrentAccount: success.accountIDToMarkForSwitchLaunch == currentID,
            successNotificationKeyHasCurrentAccountID: success.notification?.key.contains(currentID.uuidString) == true,
            successNotificationMinInterval: success.notification?.minInterval,
            failureMarkedPreviousAccount: failure.accountIDToMarkForSwitchLaunch == previousID,
            failureNotificationKey: failure.notification?.key,
            failureNotificationBody: failure.notification?.body,
            missingPreviousMarkedAccountID: missingPrevious.accountIDToMarkForSwitchLaunch,
            missingPreviousNotificationKey: missingPrevious.notification?.key
        )
    }

    @MainActor
    static func debugManualSwitchDecisionProbe() -> ManualSwitchDecisionDebugProbe {
        let officialID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F6")!
        let relayID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F7")!
        let officialAccount = AgentAccount(
            id: officialID,
            name: "Official Account",
            usedUnits: 21,
            quota: 100,
            chatGPTAccountID: "official",
            isPaid: true
        )
        let relayAccount = AgentAccount(
            id: relayID,
            name: "Relay Account",
            usedUnits: 0,
            quota: 100,
            apiToken: "sk-debug-1234",
            credentialType: .relayAPIKey,
            relayProviderID: "debug_provider",
            relayProviderName: "Debug Provider",
            relayBaseURL: "https://relay.example.com/v1",
            relayWireAPI: AgentAccount.defaultRelayWireAPI,
            relayRequiresOpenAIAuth: false
        )

        func output(
            didSwitchAuth: Bool,
            error: String? = nil
        ) -> PoolDashboardSwitchLaunchFlowCoordinator.Output {
            var viewState = PoolDashboardViewState()
            viewState.switchLaunchError = error
            return PoolDashboardSwitchLaunchFlowCoordinator.Output(
                viewModel: LocalOAuthImportViewModel(),
                viewState: viewState,
                sessionAuthorizedAuthFileURL: nil,
                didSwitchAuth: didSwitchAuth
            )
        }

        func routeName(_ route: ManualSwitchRoute) -> String {
            switch route {
            case .missing:
                return "missing"
            case .relay:
                return "relay"
            case .official:
                return "official"
            }
        }

        var view = PoolDashboardView(store: debugTransientStore())
        view._state = State(
            initialValue: AccountPoolState(
                accounts: [officialAccount, relayAccount],
                mode: .manual
            )
        )
        let success = view.manualSwitchDecision(
            account: officialAccount,
            output: output(didSwitchAuth: true)
        )
        let failure = view.manualSwitchDecision(
            account: officialAccount,
            output: output(didSwitchAuth: false, error: "Manual boom")
        )
        let emptyFailure = view.manualSwitchDecision(
            account: officialAccount,
            output: output(didSwitchAuth: false)
        )

        return ManualSwitchDecisionDebugProbe(
            missingRoute: routeName(view.manualSwitchRoute(for: UUID())),
            relayRoute: routeName(view.manualSwitchRoute(for: relayID)),
            officialRoute: routeName(view.manualSwitchRoute(for: officialID)),
            successMarkedAccount: success.accountIDToMarkForSwitchLaunch == officialID,
            successNotificationKeyContainsAccountID: success.notification?.key.contains(officialID.uuidString) == true,
            successNotificationMinInterval: success.notification?.minInterval,
            failureNotificationKey: failure.notification?.key,
            failureNotificationBody: failure.notification?.body,
            emptyFailureNotificationKey: emptyFailure.notification?.key
        )
    }

    @MainActor
    static func debugLowUsageAlertTransitionProbe() -> LowUsageAlertTransitionDebugProbe {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let lowID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A9")!
        let nextID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B9")!
        let lowAccount = AgentAccount(
            id: lowID,
            name: "low@example.com",
            usedUnits: 92,
            quota: 100,
            chatGPTAccountID: "low",
            isPaid: true
        )
        let nextAccount = AgentAccount(
            id: nextID,
            name: "next@example.com",
            usedUnits: 12,
            quota: 100,
            chatGPTAccountID: "next",
            isPaid: true
        )

        func state(
            activeAccountID: UUID,
            mode: SwitchMode = .intelligent,
            alertsEnabled: Bool = true
        ) -> AccountPoolState {
            var state = AccountPoolState(
                accounts: [lowAccount, nextAccount],
                mode: mode,
                lowUsageThresholdRatio: 0.15,
                lowUsageAlertsEnabled: alertsEnabled
            )
            state.markActiveAccountForSwitchLaunch(activeAccountID, now: now)
            return state
        }

        func transition(
            previous: AccountPoolState,
            current: AccountPoolState
        ) -> (didShow: Bool, message: String?) {
            let view = PoolDashboardView(store: debugTransientStore())
            let message = view.lowUsageAlertMessageForThresholdTriggeredIntelligentSwitch(
                previousSnapshot: previous.snapshot,
                currentSnapshot: current.snapshot
            )
            return (message != nil, message)
        }

        let disabled = transition(
            previous: state(activeAccountID: lowID, alertsEnabled: false),
            current: state(activeAccountID: nextID)
        )
        let modeChange = transition(
            previous: state(activeAccountID: lowID, mode: .manual),
            current: state(activeAccountID: nextID)
        )
        let sameAccount = transition(
            previous: state(activeAccountID: lowID),
            current: state(activeAccountID: lowID)
        )
        let thresholdExceeded = transition(
            previous: state(activeAccountID: lowID),
            current: state(activeAccountID: nextID)
        )

        return LowUsageAlertTransitionDebugProbe(
            disabledAlertsDidShow: disabled.didShow,
            modeChangeDidShow: modeChange.didShow,
            sameAccountDidShow: sameAccount.didShow,
            thresholdExceededDidShow: thresholdExceeded.didShow,
            thresholdAlertMessageContainsAccountName: thresholdExceeded.message?.contains(lowAccount.name) == true
        )
    }

    @MainActor
    static func debugLowUsageDesktopNotificationProbe() -> LowUsageDesktopNotificationDebugProbe {
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C9")!
        let account = AgentAccount(
            id: accountID,
            name: "notify-low@example.com",
            usedUnits: 92,
            quota: 100,
            isPaid: true
        )

        func state(alertsEnabled: Bool = true) -> AccountPoolState {
            var state = AccountPoolState(
                accounts: [account],
                mode: .intelligent,
                lowUsageAlertThresholdRatio: 0.2,
                lowUsageAlertsEnabled: alertsEnabled
            )
            state.markActiveAccountForSwitchLaunch(accountID, now: Date(timeIntervalSince1970: 1_800_000_100))
            return state
        }

        func viewState(
            showingAlert: Bool,
            message: String? = nil
        ) -> PoolDashboardViewState {
            var viewState = PoolDashboardViewState()
            viewState.showLowUsageAlert = showingAlert
            viewState.lowUsageAlertMessage = message
            return viewState
        }

        let hiddenAlert = Self.lowUsageDesktopNotificationRequestIfNeeded(
            state: state(),
            viewState: viewState(showingAlert: false),
            wasShowingLowUsageAlert: false
        )
        let previouslyShowing = Self.lowUsageDesktopNotificationRequestIfNeeded(
            state: state(),
            viewState: viewState(showingAlert: true, message: "Explicit low usage message"),
            wasShowingLowUsageAlert: true
        )
        let disabled = Self.lowUsageDesktopNotificationRequestIfNeeded(
            state: state(alertsEnabled: false),
            viewState: viewState(showingAlert: true, message: "Explicit low usage message"),
            wasShowingLowUsageAlert: false
        )
        let explicit = Self.lowUsageDesktopNotificationRequestIfNeeded(
            state: state(),
            viewState: viewState(showingAlert: true, message: "Explicit low usage message"),
            wasShowingLowUsageAlert: false
        )
        let fallback = Self.lowUsageDesktopNotificationRequestIfNeeded(
            state: state(),
            viewState: viewState(showingAlert: true),
            wasShowingLowUsageAlert: false
        )

        return LowUsageDesktopNotificationDebugProbe(
            disabledAlertsRequestIsNil: disabled == nil,
            previouslyShowingRequestIsNil: previouslyShowing == nil,
            hiddenAlertRequestIsNil: hiddenAlert == nil,
            explicitMessageKey: explicit?.key,
            explicitMessageTitleContainsLowUsage: explicit?.title.contains(L10n.text("alert.low_usage.title")) == true,
            explicitMessageBody: explicit?.body,
            explicitMessageMinInterval: explicit?.minInterval,
            fallbackMessageContainsAccountName: fallback?.body.contains(account.name) == true
        )
    }

    @MainActor
    static func debugRelaySwitchPreparationProbe() -> RelaySwitchPreparationDebugProbe {
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F3")!
        let vaultAPIKey = "sk-vault-1234"
        let relayAccount = AgentAccount(
            id: accountID,
            name: "Relay",
            usedUnits: 0,
            quota: 100,
            apiToken: "",
            credentialType: .relayAPIKey,
            relayProviderID: "debug_provider",
            relayProviderName: "Debug Provider",
            relayBaseURL: "https://relay.example.com/v1",
            relayWireAPI: AgentAccount.defaultRelayWireAPI,
            relayRequiresOpenAIAuth: false
        )
        let store = DebugProbeAccountPoolStore(
            snapshot: AccountPoolState(accounts: [relayAccount], mode: .manual).snapshot,
            tokenByAccountID: [accountID: vaultAPIKey]
        )
        var view = PoolDashboardView(store: store)
        view._state = State(initialValue: AccountPoolState(accounts: [relayAccount], mode: .manual))
        let prepared = view.prepareRelaySwitchRequest(for: accountID)

        let missingID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F4")!
        let failed = view.prepareRelaySwitchRequest(for: missingID)

        return RelaySwitchPreparationDebugProbe(
            preparedHydratedFromVault: prepared.hydratedFromVault,
            preparedRequestUsedVaultAPIKey: prepared.request?.apiKey == vaultAPIKey,
            preparedRequestAPIKeyLength: prepared.request?.apiKey.count,
            preparedDiagnosticContainsPreparedStage: prepared.diagnosticLog.contains("stage=prepared"),
            failedDiagnosticContainsPrepareFailedStage: failed.diagnosticLog.contains("stage=prepare_failed"),
            failedErrorDescriptionNotEmpty: !(failed.errorDescription ?? "").isEmpty
        )
    }

    @MainActor
    static func debugRelaySwitchOutcomeDecisionProbe() -> RelaySwitchOutcomeDecisionDebugProbe {
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F5")!
        let relayAccount = AgentAccount(
            id: accountID,
            name: "Relay Account",
            usedUnits: 12,
            quota: 100,
            apiToken: "sk-debug-1234",
            credentialType: .relayAPIKey,
            relayProviderID: "debug_provider",
            relayProviderName: "Debug Provider",
            relayBaseURL: "https://relay.example.com/v1",
            relayWireAPI: AgentAccount.defaultRelayWireAPI,
            relayRequiresOpenAIAuth: false
        )
        let store = DebugProbeAccountPoolStore(
            snapshot: AccountPoolState(accounts: [relayAccount], mode: .manual).snapshot,
            tokenByAccountID: [:]
        )
        let view = PoolDashboardView(store: store)
        let request = try! PoolDashboardRelayAccountCoordinator.SwitchRequest(account: relayAccount)

        func output(didSwitchAuth: Bool, error: String? = nil) -> PoolDashboardRelayAccountCoordinator.SwitchOutput {
            var viewState = PoolDashboardViewState()
            viewState.switchLaunchError = error
            return PoolDashboardRelayAccountCoordinator.SwitchOutput(
                viewState: viewState,
                didSwitchAuth: didSwitchAuth
            )
        }

        let success = view.relaySwitchOutcomeDecision(
            request: request,
            output: output(didSwitchAuth: true)
        )
        let failure = view.relaySwitchOutcomeDecision(
            request: request,
            output: output(didSwitchAuth: false, error: "Relay boom")
        )
        let emptyFailure = view.relaySwitchOutcomeDecision(
            request: request,
            output: output(didSwitchAuth: false)
        )

        return RelaySwitchOutcomeDecisionDebugProbe(
            successMarkedRelayAccount: success.accountIDToMarkForSwitchLaunch == accountID,
            successNotificationKeyContainsRelayAccountID: success.notification?.key.contains(accountID.uuidString) == true,
            successNotificationBodyContainsRelayAccountName: success.notification?.body.contains(relayAccount.name) == true,
            failureNotificationKey: failure.notification?.key,
            failureNotificationBody: failure.notification?.body,
            emptyFailureNotificationKey: emptyFailure.notification?.key
        )
    }

    @MainActor
    static func debugUsageSyncStuckRecoveryProbe() -> PoolDashboardUsageSyncStuckRecoveryDebugProbe {
        let matchingRunID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let staleRunID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        var syncingViewState = PoolDashboardViewState()
        syncingViewState.isSyncingUsage = true
        syncingViewState.usageSyncStartedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let matchingOutput = usageSyncStuckRecoveryOutput(
            runID: matchingRunID,
            currentRunID: matchingRunID,
            viewState: syncingViewState
        )
        let staleOutput = usageSyncStuckRecoveryOutput(
            runID: staleRunID,
            currentRunID: matchingRunID,
            viewState: syncingViewState
        )

        var matchingView = PoolDashboardView(store: debugTransientStore())
        matchingView._viewState = State(initialValue: syncingViewState)
        matchingView._usageSyncRunID = State(initialValue: matchingRunID)
        matchingView.forceEndUsageSyncIfStuck(runID: matchingRunID)

        return PoolDashboardUsageSyncStuckRecoveryDebugProbe(
            matchingRunIsSyncing: matchingOutput?.viewState.isSyncingUsage ?? true,
            matchingRunIDWasCleared: matchingOutput?.usageSyncRunID == nil,
            matchingErrorContainsTimeout: matchingOutput?.viewState.syncError?.contains(
                L10n.text("usage.sync.error.timeout")
            ) == true,
            staleRunStayedSyncing: staleOutput == nil && syncingViewState.isSyncingUsage,
            staleRunIDWasPreserved: staleOutput == nil
        )
    }

    @MainActor
    static func debugDataModeReloadProbe() -> PoolDashboardDataModeReloadDebugProbe {
        let loadedAccount = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!,
            name: "loaded@example.com",
            groupName: "Loaded",
            usedUnits: 12,
            quota: 100
        )
        var loadedSnapshot = AccountPoolState(accounts: [loadedAccount], mode: .manual).snapshot
        loadedSnapshot.groups = ["Loaded"]

        let fallbackAccount = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D2")!,
            name: "fallback@example.com",
            usedUnits: 0,
            quota: 100
        )
        let loadedOutput = dataModeReloadOutput(
            snapshot: loadedSnapshot,
            selectedGroupName: "Missing",
            defaultAccounts: [],
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let fallbackOutput = dataModeReloadOutput(
            snapshot: nil,
            selectedGroupName: "Missing",
            defaultAccounts: [fallbackAccount],
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let store = DebugProbeAccountPoolStore(
            snapshot: loadedSnapshot,
            tokenByAccountID: [:]
        )
        var view = PoolDashboardView(store: store)
        view._selectedGroupName = State(initialValue: "Missing")
        view.reloadStateForCurrentDataMode()

        return PoolDashboardDataModeReloadDebugProbe(
            loadedAccountNames: loadedOutput.state.accounts.map(\.name),
            loadedSelectedGroupName: loadedOutput.selectedGroupName,
            fallbackAccountCount: fallbackOutput.state.accounts.count,
            fallbackSelectedGroupName: fallbackOutput.selectedGroupName,
            actualReloadWasExercised: true
        )
    }

    @MainActor
    static func debugAddAccountProbe() -> PoolDashboardAddAccountDebugProbe {
        var initialState = AccountPoolState(accounts: [], mode: .manual)
        _ = initialState.createGroup("Ops")
        var formState = PoolDashboardFormState()
        formState.newAccountName = "pending@example.com"
        formState.newAccountQuota = 999

        let blankOutput = addAccountHandlingOutput(
            state: initialState,
            formState: formState,
            selectedGroupName: "Ops",
            name: "   ",
            quota: 250
        )
        let output = addAccountHandlingOutput(
            state: initialState,
            formState: formState,
            selectedGroupName: "Ops",
            name: "  new@example.com  ",
            quota: 250
        )

        var view = PoolDashboardView(store: debugTransientStore())
        view._state = State(initialValue: initialState)
        view._formState = State(initialValue: formState)
        view._selectedGroupName = State(initialValue: "Ops")
        view.handleAddAccount(name: "   ", quota: 250)
        view.handleAddAccount(name: "  new@example.com  ", quota: 250)

        let addedAccount = output?.state.accounts.first
        return PoolDashboardAddAccountDebugProbe(
            addedAccountNames: output?.state.accounts.map(\.name) ?? [],
            addedGroupName: addedAccount?.groupName,
            addedQuota: addedAccount?.quota,
            blankInputWasIgnored: blankOutput == nil,
            formNameWasReset: output?.formState.newAccountName.isEmpty == true,
            formQuotaWasReset: output?.formState.newAccountQuota == PoolDashboardFormState.defaultQuota
        )
    }

    @MainActor
    static func debugDeleteGroupProbe() -> PoolDashboardDeleteGroupDebugProbe {
        let defaultID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
        let redAID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E2")!
        let redBID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E3")!
        let targetGroup = "Team Red"
        let accounts = [
            AgentAccount(
                id: defaultID,
                name: "default@example.com",
                groupName: AgentAccount.defaultGroupName,
                usedUnits: 10,
                quota: 100,
                apiToken: "sk-default"
            ),
            AgentAccount(
                id: redAID,
                name: "red-a@example.com",
                groupName: targetGroup,
                usedUnits: 20,
                quota: 100,
                apiToken: "sk-red-a"
            ),
            AgentAccount(
                id: redBID,
                name: "red-b@example.com",
                groupName: targetGroup,
                usedUnits: 30,
                quota: 100,
                apiToken: "sk-red-b"
            )
        ]
        let state = AccountPoolState(accounts: accounts, mode: .manual)
        let accountNameByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        let recorder = DebugTokenRemovalRecorder()
        let store = DebugProbeAccountPoolStore(
            snapshot: state.snapshot,
            tokenByAccountID: [:],
            onRemoveToken: { recorder.append($0) }
        )
        var view = PoolDashboardView(store: store)
        view._state = State(initialValue: state)
        view._selectedGroupName = State(initialValue: targetGroup)

        let missingOutput = deleteGroupHandlingOutput(
            state: state,
            selectedGroupName: targetGroup,
            name: "Missing Group"
        )
        let output = deleteGroupHandlingOutput(
            state: state,
            selectedGroupName: targetGroup,
            name: targetGroup
        )

        view.handleDeleteGroup(name: "Missing Group")
        let missingGroupRemovedTokens = !recorder.accountIDs.isEmpty
        view.handleDeleteGroup(name: targetGroup)

        return PoolDashboardDeleteGroupDebugProbe(
            remainingAccountNames: output?.state.accounts.map(\.name) ?? [],
            removedTokenAccountNames: recorder.accountIDs.compactMap { accountNameByID[$0] },
            selectedGroupName: output?.selectedGroupName ?? "",
            missingGroupRemovedTokens: missingOutput != nil || missingGroupRemovedTokens
        )
    }

    static func debugAppUpdatePromptID(latestVersion: String) -> String {
        let release = AppUpdateRelease(
            tagName: latestVersion,
            name: latestVersion,
            htmlURL: URL(string: "https://example.com/release")!,
            publishedAt: nil,
            assets: []
        )
        return AppUpdatePrompt(
            currentVersion: "0.0.0",
            latestVersion: latestVersion,
            release: release
        ).id
    }

    static func debugUsesStackedDashboardChrome(availableWidth: CGFloat) -> Bool {
        usesStackedDashboardChrome(availableWidth: availableWidth)
    }

    static func debugUsesStackedWorkspaceContent(availableWidth: CGFloat) -> Bool {
        usesStackedWorkspaceContent(availableWidth: availableWidth)
    }

    @MainActor
    static func debugUsageAnalyticsStableDetailSectionsView(
        analyticsState: UsageAnalyticsState,
        accounts: [AgentAccount],
        selectedAccountKey: String?
    ) -> some View {
        UsageAnalyticsStableDetailSectionsView(
            analyticsState: analyticsState,
            accounts: accounts,
            selectedAccountKey: selectedAccountKey
        )
    }

    @MainActor
    static func debugScheduleWorkspacePanelView(accounts: [AgentAccount]) -> some View {
        ScheduleWorkspacePanelView(accounts: accounts)
    }

    @MainActor
    static func debugScheduleEventSummaries(
        accounts: [AgentAccount],
        start: Date,
        end: Date
    ) -> [ScheduleEventDebugSummary] {
        ScheduleWorkspacePanelView.debugEventSummaries(accounts: accounts, start: start, end: end)
    }

    @MainActor
    static func debugDailyUsagePlanningWorkspacePanelView(
        accounts: [AgentAccount],
        analyticsState: UsageAnalyticsState
    ) -> some View {
        DailyUsagePlanningWorkspacePanelView(
            accounts: accounts,
            analyticsState: analyticsState
        )
    }

    @MainActor
    static func debugDailyUsagePlanningNotificationBodies(account: AgentAccount) -> [String: String] {
        DailyUsagePlanningWorkspacePanelView.debugNotificationBodies(account: account)
    }

    @MainActor
    static func debugDailyUsagePlanningNotificationTitles(account: AgentAccount) -> [String: String] {
        DailyUsagePlanningWorkspacePanelView.debugNotificationTitles(account: account)
    }

    @MainActor
    static func debugDailyUsagePlanningBudgetPersistenceProbe(
        account: AgentAccount
    ) -> (afterSetBudget: Int?, afterClearBudget: Int?, notifiedLevel: String?) {
        DailyUsagePlanningWorkspacePanelView.debugBudgetPersistenceProbe(account: account)
    }

    @MainActor
    static func debugDailyUsagePlanningStatusCallouts(account: AgentAccount) -> some View {
        DailyUsagePlanningWorkspacePanelView.debugStatusCallouts(account: account)
    }

    @MainActor
    static func debugDailyUsagePlanningNotificationEvaluationProbe(
    ) -> DailyUsagePlanningNotificationEvaluationDebugProbe {
        DailyUsagePlanningWorkspacePanelView.debugNotificationEvaluationProbe()
    }

    @MainActor
    static func debugUsageAnalyticsWorkspacePanelView(
        analyticsState: UsageAnalyticsState,
        accounts: [AgentAccount],
        onClearIdleDelay: @escaping (String?) -> Void = { _ in }
    ) -> some View {
        UsageAnalyticsWorkspacePanelView(
            analyticsState: analyticsState,
            accounts: accounts,
            onClearIdleDelay: onClearIdleDelay
        )
    }

    @MainActor
    static func debugUsageAnalyticsWorkspaceVariantView(
        analyticsState: UsageAnalyticsState,
        accounts: [AgentAccount],
        analysisBasisID: String,
        chartGranularityID: String,
        accountSortModeID: String,
        selectedAccountKey: String?,
        onClearIdleDelay: @escaping (String?) -> Void = { _ in }
    ) -> some View {
        UsageAnalyticsWorkspacePanelView.debugConfigured(
            analyticsState: analyticsState,
            accounts: accounts,
            analysisBasisID: analysisBasisID,
            chartGranularityID: chartGranularityID,
            accountSortModeID: accountSortModeID,
            selectedAccountKey: selectedAccountKey,
            onClearIdleDelay: onClearIdleDelay
        )
    }

    @MainActor
    static func debugUsageAnalyticsWorkspaceProbe(
        analyticsState: UsageAnalyticsState,
        accounts: [AgentAccount],
        selectedAccountKey: String?,
        days: Int,
        weeks: Int
    ) -> UsageAnalyticsWorkspaceDebugProbe {
        UsageAnalyticsWorkspacePanelView.debugProbe(
            analyticsState: analyticsState,
            accounts: accounts,
            selectedAccountKey: selectedAccountKey,
            days: days,
            weeks: weeks
        )
    }

    @MainActor
    static func debugUsageAnalyticsWorkspacePrivateDetailViews(
        analyticsState: UsageAnalyticsState,
        accounts: [AgentAccount],
        selectedAccountKey: String?
    ) -> some View {
        UsageAnalyticsWorkspacePanelView.debugPrivateDetailViews(
            analyticsState: analyticsState,
            accounts: accounts,
            selectedAccountKey: selectedAccountKey
        )
    }

    @MainActor
    static func debugUsageAnalyticsWorkspacePrivateCoverageViews(
        analyticsState: UsageAnalyticsState,
        accounts: [AgentAccount],
        selectedAccountKey: String?
    ) -> some View {
        UsageAnalyticsWorkspacePanelView.debugPrivateCoverageViews(
            analyticsState: analyticsState,
            accounts: accounts,
            selectedAccountKey: selectedAccountKey
        )
    }

    @MainActor
    static func debugClearUsageAnalyticsIdleDelayProbe(
        records: [UsageAnalyticsRecord]
    ) -> (targeted: [Int], all: [Int]) {
        let defaults = UserDefaults.standard
        let backup = defaults.object(forKey: usageAnalyticsStateKey)
        defer {
            if let backup {
                defaults.set(backup, forKey: usageAnalyticsStateKey)
            } else {
                defaults.removeObject(forKey: usageAnalyticsStateKey)
            }
        }

        func makeView() -> PoolDashboardView {
            var view = PoolDashboardView(store: debugTransientStore())
            let state = UsageAnalyticsState(
                records: records,
                snapshots: [],
                thresholdEvents: [],
                switchEvents: [],
                lastActiveAccountKey: records.first?.activeAccountKeyAtSync,
                lastUpdatedAt: records.first?.timestamp
            )
            view._usageAnalyticsState = State(initialValue: state)
            view._usageAnalyticsStateLoaded = State(initialValue: true)
            return view
        }

        let sourceState = UsageAnalyticsState(
            records: records,
            snapshots: [],
            thresholdEvents: [],
            switchEvents: [],
            lastActiveAccountKey: records.first?.activeAccountKeyAtSync,
            lastUpdatedAt: records.first?.timestamp
        )
        let targetedAccountKey = records.first?.accountKey

        let targetedView = makeView()
        targetedView.clearUsageAnalyticsIdleDelay(accountKey: targetedAccountKey)

        let allView = makeView()
        allView.clearUsageAnalyticsIdleDelay(accountKey: nil)

        let targetedState = usageAnalyticsStateClearingIdleDelay(
            sourceState,
            accountKey: targetedAccountKey
        )
        let allState = usageAnalyticsStateClearingIdleDelay(
            sourceState,
            accountKey: nil
        )

        return (
            targeted: targetedState.records.map(\.weeklyIdleDelayMinutes),
            all: allState.records.map(\.weeklyIdleDelayMinutes)
        )
    }

    @MainActor
    static func debugAppUpdateOverlayView(releaseNotes: String?) -> some View {
        let view = PoolDashboardView(store: debugTransientStore())
        let release = AppUpdateRelease(
            tagName: "v9.9.9",
            name: "Debug Release",
            htmlURL: URL(string: "https://example.com/releases/v9.9.9")!,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000),
            body: releaseNotes,
            assets: []
        )
        let prompt = AppUpdatePrompt(
            currentVersion: "1.0.0",
            latestVersion: "9.9.9",
            release: release
        )
        return view.appUpdateOverlay(prompt: prompt)
    }

    @MainActor
    static func debugWhatsNewOverlayView() -> some View {
        let view = PoolDashboardView(store: debugTransientStore())
        let announcement = WhatsNewAnnouncement.current(version: "1.0.14", build: "118")
        return view.whatsNewOverlay(announcement: announcement)
    }

    @MainActor
    static func debugSpecialResetWatchPanelView(store: AccountPoolStoring) -> some View {
        let view = PoolDashboardView(store: store)
        return view.specialResetWatchPanel
    }

    @MainActor
    static func debugPopulatedSpecialResetWatchPanelView() -> some View {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let account = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A551")!,
            name: "populated-reset@example.com",
            usedUnits: 12,
            quota: 100,
            usageWindowResetAt: now.addingTimeInterval(6 * 24 * 3_600),
            primaryUsagePercent: 8,
            primaryUsageResetAt: now.addingTimeInterval(4 * 3_600),
            secondaryUsagePercent: 12,
            secondaryUsageResetAt: now.addingTimeInterval(6 * 24 * 3_600),
            isPaid: true
        )
        var state = AccountPoolState(accounts: [account], mode: .manual)
        state.markActiveAccountForSwitchLaunch(account.id, now: now)

        var view = PoolDashboardView(store: debugTransientStore())
        view._state = State(initialValue: state)

        let accountKey = view.specialResetWatchAccountKey(for: account)
        let previousWeekly = now.addingTimeInterval(24 * 3_600)
        let observedWeekly = now.addingTimeInterval(8 * 24 * 3_600)
        let previousFiveHour = now.addingTimeInterval(2 * 3_600)
        let observedFiveHour = now.addingTimeInterval(7 * 3_600)
        var watchState = SpecialResetWatchState()
        watchState.records = [
            SpecialResetRecord(
                accountKey: accountKey,
                accountName: view.normalizedSpecialResetAccountName(account),
                expectedWeeklyResetAt: observedWeekly,
                expectedFiveHourResetAt: observedFiveHour,
                lastObservedWeeklyResetAt: account.secondaryUsageResetAt,
                lastObservedFiveHourResetAt: account.primaryUsageResetAt,
                lastSeenWeeklyUsagePercent: 12,
                lastSeenUsedUnits: 12,
                lastSeenFiveHourUsagePercent: 8,
                lastSeenAt: now
            )
        ]
        watchState.events = [
            SpecialResetEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000E551")!,
                detectedAt: now.addingTimeInterval(60),
                accountKey: accountKey,
                accountName: view.normalizedSpecialResetAccountName(account),
                previousWeeklyExpectedAt: previousWeekly,
                observedWeeklyNextResetAt: observedWeekly,
                previousFiveHourExpectedAt: previousFiveHour,
                observedFiveHourNextResetAt: observedFiveHour
            )
        ]
        watchState.lastEvaluatedAt = now
        watchState.lastNotificationAt = now.addingTimeInterval(60)
        view._specialResetWatchState = State(initialValue: watchState)

        return view.specialResetWatchPanel
    }

    @MainActor
    static func debugDeveloperContextPanelView(store: AccountPoolStoring) -> some View {
        let view = PoolDashboardView(store: store)
        return view.developerContextPanel
    }

    @MainActor
    static func debugDebugToolsPanelView(store: AccountPoolStoring) -> some View {
        let view = PoolDashboardView(store: store)
        return view.debugToolsPanel
    }

    @MainActor
    static func debugPrivateSettingsPanelViews(store: AccountPoolStoring) -> some View {
        let view = PoolDashboardView(store: store)
        let release = AppUpdateRelease(
            tagName: "v9.9.9",
            name: "Debug Release",
            htmlURL: URL(string: "https://example.com/releases/v9.9.9")!,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000),
            body: "Debug release notes",
            assets: []
        )
        let prompt = AppUpdatePrompt(
            currentVersion: "1.0.0",
            latestVersion: "9.9.9",
            release: release
        )

        return HStack(alignment: .top, spacing: 12) {
            view.collapsedSidebarHandle
            VStack(alignment: .leading, spacing: 12) {
                view.sidebarUpdateButton(prompt: prompt)
                view.strategySettingsPanel
                view.workspaceSettingsPanel
            }
        }
    }

    @MainActor
    static func debugPrivateDashboardPanelViews(store: AccountPoolStoring) -> some View {
        let view = PoolDashboardView(store: store)
        return VStack(alignment: .leading, spacing: 12) {
            view.dashboardHeaderChrome(availableWidth: 820)
            view.dashboardHeaderChrome(availableWidth: 1_200)
            view.syncToolbarPanel
            view.activeAccountPanel
            view.accountUsagePanel(availableWidth: 1_200)
        }
    }

    @MainActor
    static func debugPairedPanelsView() -> some View {
        let view = PoolDashboardView(store: debugTransientStore())
        return view.pairedPanels(
            primary: Text("Primary debug panel")
                .frame(maxWidth: .infinity, minHeight: 120)
                .dashboardInfoCard(),
            secondary: Text("Secondary debug panel")
                .frame(maxWidth: .infinity, minHeight: 120)
                .dashboardInfoCard()
        )
    }

    @MainActor
    static func debugDiagnosticsSnapshot(store: AccountPoolStoring) -> [DebugDiagnosticMetric] {
        let view = PoolDashboardView(store: store)
        return view.debugDiagnostics
    }

    static func debugDesktopNotifierThrottleSequence(
        minInterval: TimeInterval
    ) -> (first: Bool, second: Bool, afterReset: Bool) {
        DesktopNotifier.debugThrottleSequence(minInterval: minInterval)
    }

    @MainActor
    static func debugCoreCoverageSnapshot(
        store: AccountPoolStoring
    ) -> (
        selectedLaunchTargetRaw: String,
        selectedLaunchTarget: CodexLaunchTarget,
        isDebugBuild: Bool,
        defaultAccountCount: Int,
        defaultStateMode: SwitchMode,
        firstAccountName: String,
        firstAccountQuota: Int,
        strategyMode: SwitchMode
    ) {
        let view = PoolDashboardView(store: store)

        let firstAccountID = view.state.accounts.first?.id ?? UUID()
        let firstName = view.accountBindings.nameBinding(for: firstAccountID).wrappedValue
        let firstQuota = view.accountBindings.quotaBinding(for: firstAccountID).wrappedValue
        let strategyMode = view.strategyBindings.mode.wrappedValue
        let defaultStateMode = makeDefaultState(accounts: []).mode

        return (
            selectedLaunchTargetRaw: view.switchLaunchTargetRaw,
            selectedLaunchTarget: view.selectedLaunchTarget,
            isDebugBuild: view.isDebugBuild,
            defaultAccountCount: defaultAccounts.count,
            defaultStateMode: defaultStateMode,
            firstAccountName: firstName,
            firstAccountQuota: firstQuota,
            strategyMode: strategyMode
        )
    }

    private static func debugTransientStore() -> AccountPoolStoring {
        let suiteName = "CodexPoolManager.DebugOverlay.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        return UserDefaultsAccountPoolStore(
            defaults: defaults,
            key: "debug_account_pool_snapshot"
        )
    }

    @MainActor
    static func debugApplySnapshotChange(
        store: AccountPoolStoring,
        runtimeModel: AppPoolRuntimeModel?,
        previousState: AccountPoolState,
        nextState: AccountPoolState
    ) {
        let view = PoolDashboardView(store: store, runtimeModel: runtimeModel)
        view.handleSnapshotChange(
            nextState.snapshot,
            previousSnapshot: previousState.snapshot,
            currentState: nextState
        )
    }
}
#endif

#Preview {
    PoolDashboardView(store: UserDefaultsAccountPoolStore(defaults: .standard, key: "preview_account_pool_snapshot"))
}
