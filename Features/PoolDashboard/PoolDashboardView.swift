import SwiftUI
import UserNotifications
#if canImport(AppKit)
import AppKit
#endif

struct PoolDashboardView: View {
    private enum SyncPolicy {
        static let timeoutNanoseconds: UInt64 = 45_000_000_000
        static let stuckRecoveryNanoseconds: UInt64 = 70_000_000_000
    }
    private static let codexAuthBookmarkKey = "codex_auth_json_bookmark"
    private static let defaultOAuthClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let productionSnapshotKey = "account_pool_snapshot"
    private static let productionTokenKey = "account_pool_tokens"
    private static let developerSnapshotKey = "account_pool_snapshot_developer"
    private static let developerTokenKey = "account_pool_tokens_developer"
    private static let developerMockModeKey = "pool_dashboard.developer.mock_mode"
    private static let specialResetWatchStateKey = "pool_dashboard.special_reset_watch_state"
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
        let kind: SpecialResetKind
        let previousExpectedAt: Date
        let observedNextResetAt: Date
    }
    private struct SpecialResetWatchState: Codable {
        var records: [SpecialResetRecord] = []
        var events: [SpecialResetEvent] = []
        var lastEvaluatedAt: Date?
    }
    private struct SpecialResetDetection {
        let accountKey: String
        let accountName: String
        let kind: SpecialResetKind
        let previousExpectedAt: Date
        let observedNextResetAt: Date
        let detectedAt: Date
    }
    @AppStorage("oauth_issuer") private var oauthIssuer = "https://auth.openai.com"
    @AppStorage("oauth_client_id") private var oauthClientID = Self.defaultOAuthClientID
    @AppStorage("oauth_scopes") private var oauthScopes = "openid profile email offline_access  api.connectors.read api.connectors.invoke"
    @AppStorage("oauth_redirect_uri") private var oauthRedirectURI = "http://localhost:1455/auth/callback"
    @AppStorage("oauth_originator") private var oauthOriginator = "codex_cli_rs"
    @AppStorage("oauth_workspace_id") private var oauthWorkspaceID = ""
    @AppStorage(L10n.languageOverrideKey) private var appLanguageOverride = L10n.systemLanguageCode
    @AppStorage(AppAppearancePreference.storageKey) private var appAppearanceOverride = AppAppearancePreference.system.rawValue
    @AppStorage(Self.developerMockModeKey) private var developerMockModeEnabled = false
    @AppStorage(Self.specialResetWatchStateKey) private var specialResetWatchStateRaw = ""
    @AppStorage("pool_dashboard.special_reset_watch_enabled") private var specialResetWatchEnabled = true
    @AppStorage("pool_dashboard.special_reset_watch_notify_enabled") private var specialResetWatchNotifyEnabled = true
    @AppStorage("pool_dashboard.special_reset_watch_grace_minutes") private var specialResetWatchGraceMinutes = 30
    @Environment(\.colorScheme) private var colorScheme
    @State private var state: AccountPoolState
    @State private var formState = PoolDashboardFormState()
    @State private var resetAllLatch = DestructiveActionLatch()
    @State private var viewState = PoolDashboardViewState()
    @State private var lowUsageAlertPolicy = LowUsageAlertPolicy()
    @State private var localOAuthImportViewModel = LocalOAuthImportViewModel()
    @State private var sessionAuthorizedAuthFileURL: URL?
    @State private var selectedWorkspace: Workspace = .authentication
    @State private var selectedGroupName: String = AgentAccount.defaultGroupName
    @State private var isWorkspaceSectionCollapsed = false
    @State private var isSidebarCollapsed = false
    @State private var themeRenderToken = 0
    @State private var suppressNextSnapshotDrivenSwitch = false
    @State private var usageSyncRunID: UUID?
    @State private var pendingManualOAuthContext: PendingManualOAuthContext?
    @State private var manualOAuthCallbackURL = ""
    @State private var oauthSignInTask: Task<Void, Never>?
    @State private var specialResetWatchState = SpecialResetWatchState()
    private let store: AccountPoolStoring
    private let backupFlowCoordinator = PoolDashboardBackupFlowCoordinator()
    private let usageSyncFlowCoordinator = PoolDashboardUsageSyncFlowCoordinator()
    private let oauthSignInFlowCoordinator = PoolDashboardOAuthSignInFlowCoordinator()
    private let lifecycleFlowCoordinator = PoolDashboardLifecycleFlowCoordinator()
    private let quickActionsFlowCoordinator = PoolDashboardQuickActionsFlowCoordinator()
    private let localAccountsFlowCoordinator = PoolDashboardLocalAccountsFlowCoordinator()
    private let localImportFlowCoordinator = PoolDashboardLocalImportFlowCoordinator()
    private let switchLaunchFlowCoordinator = PoolDashboardSwitchLaunchFlowCoordinator()
    private let usagePresenter = PoolAccountUsagePresenter()
    private let alertPresenter = PoolDashboardAlertPresenter()
    private let viewMutationCoordinator = PoolDashboardViewMutationCoordinator()
    private let asyncStateCoordinator = PoolDashboardAsyncStateCoordinator()
    private var authFileAccessService: CodexAuthFileAccessService {
        CodexAuthFileAccessService(bookmarkKey: Self.codexAuthBookmarkKey)
    }
    private var accountBindings: PoolDashboardAccountBindingAdapter {
        PoolDashboardAccountBindingAdapter(state: $state)
    }
    private var strategyBindings: PoolDashboardStrategyBindingAdapter {
        PoolDashboardStrategyBindingAdapter(state: $state)
    }

    private var autoSyncTaskID: String {
        "\(state.autoSyncEnabled)-\(Int(state.autoSyncIntervalSeconds))"
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
            case .openAIResetAlert: "bell.badge.waveform"
            case .settings: "gearshape"
            case .safety: "shield.lefthalf.filled.badge.checkmark"
            case .developer: "wrench.and.screwdriver"
            }
        }
    }

    init(store: AccountPoolStoring = DeveloperAwareAccountPoolStore()) {
        self.store = store
        if let snapshot = store.load() {
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
        }
        .frame(minWidth: PoolDashboardTheme.minWidth, minHeight: PoolDashboardTheme.minHeight)
        .onAppear {
            syncThemePaletteIfNeeded()
            handleOnAppear()
        }
        .onChange(of: state.snapshot) { previousSnapshot, snapshot in
            let wasShowingLowUsageAlert = viewState.showLowUsageAlert
            showLowUsageAlertForThresholdTriggeredIntelligentSwitch(
                previousSnapshot: previousSnapshot,
                currentSnapshot: snapshot
            )
            handleSnapshotChange(snapshot)
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
        .onChange(of: isDeveloperBuild) { _, isEnabled in
            if !isEnabled && selectedWorkspace == .developer {
                selectedWorkspace = .authentication
            }
        }
        .onChange(of: developerMockModeEnabled) { _, _ in
            guard isDeveloperBuild else { return }
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
        .onChange(of: colorScheme) { _, _ in
            syncThemePaletteIfNeeded()
        }
        .task(id: autoSyncTaskID) {
            guard state.autoSyncEnabled else { return }
            await syncCodexUsage()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(state.autoSyncIntervalSeconds * 1_000_000_000))
                if Task.isCancelled { break }
                await syncCodexUsage()
            }
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

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: PoolDashboardTheme.sectionSpacing) {
                        HStack(alignment: .top, spacing: 12) {
                            DashboardHeaderSectionView(
                                accountCount: state.uniqueAccountsCount,
                                availableCount: state.availableAccountsCount,
                                overallUsagePercent: Int(state.overallUsageRatio * 100),
                                modeTitle: state.mode.rawValue
                            )

                            syncToolbarPanel
                        }

                        accountUsagePanel
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                }

                workspaceCollapseToggle()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .background(
                        PoolDashboardTheme.panelStrongFill.opacity(PoolDashboardTheme.chromeFooterOpacity)
                            .overlay(alignment: .top) {
                                Rectangle()
                                    .fill(PoolDashboardTheme.panelInnerStroke.opacity(0.75))
                                    .frame(height: 1)
                            }
                    )

                if !isWorkspaceSectionCollapsed {
                    workspaceDrawerPanel
                }
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

    private var workspaceDrawerPanel: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(PoolDashboardTheme.panelInnerStroke.opacity(0.75))
                .frame(height: 1)

            ScrollView(showsIndicators: false) {
                workspaceContent
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .frame(minHeight: 300, maxHeight: 440, alignment: .topLeading)
            .background(PoolDashboardTheme.panelStrongFill.opacity(PoolDashboardTheme.chromeStrongOpacity))
        }
    }

    private func workspaceCollapseToggle() -> some View {
        HStack(spacing: 8) {
            Image(systemName: isWorkspaceSectionCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(PoolDashboardTheme.textMuted)
                .frame(width: 12)

            Text(selectedWorkspace.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(PoolDashboardTheme.textSecondary)

            Rectangle()
                .fill(PoolDashboardTheme.panelInnerStroke.opacity(0.9))
                .frame(height: 1)

            Text(isWorkspaceSectionCollapsed ? L10n.text("drawer.expand") : L10n.text("drawer.collapse"))
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
                isWorkspaceSectionCollapsed.toggle()
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

    private var workspaceContent: some View {
        VStack(alignment: .leading, spacing: PoolDashboardTheme.sectionSpacing) {
            PanelSectionHeaderView(
                title: selectedWorkspace.title,
                subtitle: selectedWorkspace.subtitle,
                symbolName: selectedWorkspace.symbolName
            )

            if hasWorkspaceContextPanel {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: PoolDashboardTheme.sectionSpacing) {
                        workspaceMainPanel
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        workspaceContextPanel
                            .frame(width: PoolDashboardTheme.workspaceContextWidth, alignment: .topLeading)
                    }

                    VStack(alignment: .leading, spacing: PoolDashboardTheme.sectionSpacing) {
                        workspaceMainPanel
                        workspaceContextPanel
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
        case .runtime, .schedule, .openAIResetAlert, .settings, .safety:
            return false
        default:
            return true
        }
    }

    @ViewBuilder
    private var workspaceMainPanel: some View {
        switch selectedWorkspace {
        case .authentication:
            oauthLoginPanel
        case .runtime:
            strategySettingsPanel
        case .schedule:
            schedulePanel
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

                Button("測試右上角通知") {
                    DesktopNotifier.post(
                        key: "manual-test-notification",
                        title: "Codex Pool 測試通知",
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
            if isWorkspaceSectionCollapsed {
                withAnimation(.easeInOut(duration: PoolDashboardTheme.fastAnimationDuration)) {
                    isWorkspaceSectionCollapsed = false
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

    private var syncToolbarPanel: some View {
        SyncToolbarView(
            isSyncing: viewState.isSyncingUsage,
            lastSyncAt: state.lastUsageSyncAt,
            errorText: viewState.syncError
        ) {
            Task { await syncCodexUsage() }
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

    private var localOAuthAccountsPanel: some View {
        LocalOAuthAccountsPanelView(
            accounts: localOAuthImportViewModel.accounts,
            errorMessage: localOAuthImportViewModel.errorMessage,
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
            lowUsageAlertThresholdBinding: strategyBindings.lowUsageAlertThreshold
        )
    }

    private var workspaceSettingsPanel: some View {
        WorkspaceSettingsPanelView(
            switchWithoutLaunchingBinding: strategyBindings.switchWithoutLaunching,
            autoSyncEnabledBinding: strategyBindings.autoSyncEnabled,
            autoSyncIntervalSecondsBinding: strategyBindings.autoSyncIntervalSeconds,
            languageOverrideBinding: $appLanguageOverride,
            appearanceOverrideBinding: $appAppearanceOverride,
            languageOptions: L10n.languageOptions
        )
    }

    private var schedulePanel: some View {
        ScheduleWorkspacePanelView(accounts: state.accounts)
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

                Stepper(value: $specialResetWatchGraceMinutes, in: 0...240, step: 5) {
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.accountName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(PoolDashboardTheme.textPrimary)
                                Text(
                                    L10n.text(
                                        "special_reset.records_row_format",
                                        record.expectedWeeklyResetAt.map(specialResetDateText) ?? L10n.text("schedule.summary.not_available"),
                                        record.expectedFiveHourResetAt.map(specialResetDateText) ?? L10n.text("schedule.summary.not_available")
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

    private var accountUsagePanel: some View {
        AccountUsagePanelView(
            newAccountName: $formState.newAccountName,
            newAccountQuota: $formState.newAccountQuota,
            selectedGroupName: $selectedGroupName,
            accounts: state.accounts,
            groups: state.groups,
            activeAccountID: state.activeAccountID,
            switchLaunchError: viewState.switchLaunchError,
            switchLaunchWarning: viewState.switchLaunchWarning,
            showAddAccountControls: isDeveloperBuild,
            onAddAccount: { name, quota in
                handleAddAccount(name: name, quota: quota)
            },
            onSwitchAndLaunch: { account in
                await switchAndLaunchCodex(using: account)
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
            lastSwitchLaunchLog: $viewState.lastSwitchLaunchLog
        )
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
        loadSpecialResetWatchStateFromStorage()
        DesktopNotifier.requestAuthorizationIfNeeded()

        let output = lifecycleFlowCoordinator.onAppear(
            state: state,
            lowUsageAlertPolicy: lowUsageAlertPolicy,
            viewModel: localOAuthImportViewModel,
            authFileAccessService: authFileAccessService,
            currentAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL
        )
        applyLifecycleOnAppearOutput(output)
        evaluateSpecialResetWatchAfterSync(now: .now)
        WidgetBridgePublisher.publish(from: state.snapshot)
    }

    // MARK: - Developer Data Mode

    private func reloadStateForCurrentDataMode() {
        if let snapshot = store.load() {
            state = AccountPoolState(snapshot: snapshot)
        } else {
            var defaultState = Self.makeDefaultState(accounts: Self.defaultAccounts)
            defaultState.evaluate(now: .now)
            state = defaultState
        }

        if state.groups.isEmpty {
            selectedGroupName = AgentAccount.defaultGroupName
        } else if !state.groups.contains(selectedGroupName) {
            selectedGroupName = state.groups[0]
        }

        lowUsageAlertPolicy = LowUsageAlertPolicy()
        viewState.showLowUsageAlert = false
        viewState.lowUsageAlertMessage = nil
        WidgetBridgePublisher.publish(from: state.snapshot)
    }

    private func seedDeveloperMockData() {
        guard isDeveloperBuild, developerMockModeEnabled else { return }

        var seededState = Self.makeDefaultState(accounts: Self.defaultAccounts)
        seededState.evaluate(now: .now)
        state = seededState
        store.save(seededState.snapshot)
        WidgetBridgePublisher.publish(from: seededState.snapshot)
    }

    private func clearCurrentDataModeStore() {
        let defaults = UserDefaults.standard
        if isDeveloperBuild && developerMockModeEnabled {
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

    private func handleSnapshotChange(_ snapshot: AccountPoolSnapshot) {
        WidgetBridgePublisher.publish(from: snapshot)
        let output = lifecycleFlowCoordinator.onSnapshotChanged(
            snapshot: snapshot,
            state: state,
            lowUsageAlertPolicy: lowUsageAlertPolicy,
            viewState: viewState,
            store: store
        )
        applyLifecycleSnapshotChangeOutput(output)
    }

    private func showLowUsageAlertForThresholdTriggeredIntelligentSwitch(
        previousSnapshot: AccountPoolSnapshot,
        currentSnapshot: AccountPoolSnapshot
    ) {
        guard previousSnapshot.mode == .intelligent, currentSnapshot.mode == .intelligent else { return }
        guard previousSnapshot.activeAccountID != currentSnapshot.activeAccountID else { return }
        guard let previousAccountID = previousSnapshot.activeAccountID,
              let previousAccount = previousSnapshot.accounts.first(where: { $0.id == previousAccountID })
        else {
            return
        }

        let thresholdRatio = previousSnapshot.lowUsageThresholdRatio
        guard intelligentRemainingRatio(for: previousAccount) <= thresholdRatio else { return }

        viewState.lowUsageAlertMessage = alertPresenter.lowUsageAlertMessage(
            activeAccount: previousAccount,
            thresholdRatio: thresholdRatio
        )
        viewState.showLowUsageAlert = true
    }

    private func postLowUsageDesktopNotificationIfNeeded(
        wasShowingLowUsageAlert: Bool
    ) {
        guard !wasShowingLowUsageAlert, viewState.showLowUsageAlert else { return }

        let message = viewState.lowUsageAlertMessage
            ?? alertPresenter.lowUsageAlertMessage(
                activeAccount: state.activeAccount,
                thresholdRatio: state.lowUsageAlertThresholdRatio
            )
        DesktopNotifier.post(
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
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return }
        state.addAccount(
            name: normalizedName,
            groupName: selectedGroupName,
            quota: quota
        )
        formState.resetNewAccountInput()
    }

    private func handleRemoveAccount(accountID: UUID) {
        applyQuickAction(.removeAccount(accountID))
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
        let normalized = AgentAccount.normalizedGroupName(name)
        guard state.deleteGroup(normalized) else { return }

        if selectedGroupName == normalized {
            selectedGroupName = AgentAccount.defaultGroupName
        }
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
    private func syncCodexUsage() async {
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
    private func scheduleUsageSyncStuckRecovery(for runID: UUID) {
        Task {
            try? await Task.sleep(nanoseconds: SyncPolicy.stuckRecoveryNanoseconds)
            forceEndUsageSyncIfStuck(runID: runID)
        }
    }

    @MainActor
    private func forceEndUsageSyncIfStuck(runID: UUID) {
        guard usageSyncRunID == runID, viewState.isSyncingUsage else { return }
        viewState.syncError = L10n.text(
            "sync.failure.with_description_format",
            L10n.text("sync.failure.prefix"),
            L10n.text("usage.sync.error.timeout")
        )
        usageSyncRunID = nil
        asyncStateCoordinator.endUsageSync(viewState: &viewState)
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
            currentAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL,
            authFileAccessService: authFileAccessService,
            viewModel: localOAuthImportViewModel,
            viewState: viewState,
            authorizeAuthFile: openAuthFilePanel
        )
        if output.didSwitchAuth {
            suppressNextSnapshotDrivenSwitch = true
            state.markActiveAccountForSwitchLaunch(account.id)
            DesktopNotifier.post(
                key: "auto-switch-\(account.id.uuidString)",
                title: "Codex Pool 已自動切換帳號",
                body: notificationUsageSummary(
                    for: state.accounts.first(where: { $0.id == account.id }) ?? account
                ),
                minInterval: 15
            )
        } else if let previousActiveAccountID,
                  state.accounts.contains(where: { $0.id == previousActiveAccountID }) {
            suppressNextSnapshotDrivenSwitch = true
            state.markActiveAccountForSwitchLaunch(previousActiveAccountID)
            if let errorMessage = output.viewState.switchLaunchError, !errorMessage.isEmpty {
                DesktopNotifier.post(
                    key: "auto-switch-failed",
                    title: "Codex Pool 自動切換失敗",
                    body: errorMessage,
                    minInterval: 120
                )
            }
        }
        applySwitchLaunchOutput(output)
    }

    @MainActor
    private func importLocalOAuthAccount(_ localAccount: LocalCodexOAuthAccount) async {
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
    }

    // MARK: - Switch & Launch

    @MainActor
    private func switchAndLaunchCodex(using account: AgentAccount) async {
        let output = await switchLaunchFlowCoordinator.switchAndLaunch(
            using: account,
            switchWithoutLaunching: state.switchWithoutLaunching,
            currentAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL,
            authFileAccessService: authFileAccessService,
            viewModel: localOAuthImportViewModel,
            viewState: viewState,
            authorizeAuthFile: openAuthFilePanel
        )
        if output.didSwitchAuth {
            suppressNextSnapshotDrivenSwitch = true
            state.markActiveAccountForSwitchLaunch(account.id)
            DesktopNotifier.post(
                key: "manual-switch-\(account.id.uuidString)",
                title: "Codex Pool 已切換帳號",
                body: notificationUsageSummary(
                    for: state.accounts.first(where: { $0.id == account.id }) ?? account
                ),
                minInterval: 5
            )
        } else if let errorMessage = output.viewState.switchLaunchError, !errorMessage.isEmpty {
            DesktopNotifier.post(
                key: "manual-switch-failed",
                title: "Codex Pool 切換失敗",
                body: errorMessage,
                minInterval: 120
            )
        }
        applySwitchLaunchOutput(output)
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
        let baselineRecords = state.accounts
            .filter(\.isPaid)
            .map { account in
                SpecialResetRecord(
                    accountKey: account.deduplicationKey,
                    accountName: normalizedSpecialResetAccountName(account),
                    expectedWeeklyResetAt: normalizedExpectedResetDate(
                        observedResetAt: account.usageWindowResetAt,
                        kind: .weekly,
                        now: now
                    ),
                    expectedFiveHourResetAt: normalizedExpectedResetDate(
                        observedResetAt: account.primaryUsageResetAt,
                        kind: .fiveHour,
                        now: now
                    ),
                    lastSeenUsedUnits: account.usedUnits,
                    lastSeenFiveHourUsagePercent: account.primaryUsagePercent,
                    lastSeenAt: now
                )
            }
        specialResetWatchState.records = deduplicatedSpecialResetRecords(baselineRecords)
        specialResetWatchState.events = []
        specialResetWatchState.lastEvaluatedAt = now
        persistSpecialResetWatchState()
    }

    @MainActor
    private func clearSpecialResetWatchEvents() {
        specialResetWatchState.events = []
        persistSpecialResetWatchState()
    }

    @MainActor
    private func evaluateSpecialResetWatchAfterSync(now: Date) {
        guard specialResetWatchEnabled else { return }

        let paidAccounts = state.accounts.filter(\.isPaid)
        guard !paidAccounts.isEmpty else { return }

        let graceSeconds = TimeInterval(max(0, specialResetWatchGraceMinutes) * 60)
        var recordsByKey = specialResetRecordsByKey(from: specialResetWatchState.records)
        var detections: [SpecialResetDetection] = []

        for account in paidAccounts {
            let accountKey = account.deduplicationKey
            var record = recordsByKey[accountKey] ?? SpecialResetRecord(
                accountKey: accountKey,
                accountName: normalizedSpecialResetAccountName(account)
            )
            record.accountName = normalizedSpecialResetAccountName(account)

            if let weeklyDetection = detectUnexpectedEarlyReset(
                account: account,
                kind: .weekly,
                expectedResetAt: record.expectedWeeklyResetAt,
                observedResetAt: account.usageWindowResetAt,
                previousUsageValue: record.lastSeenUsedUnits,
                currentUsageValue: account.usedUnits,
                now: now,
                graceSeconds: graceSeconds
            ) {
                detections.append(weeklyDetection)
            }
            record.expectedWeeklyResetAt = normalizedExpectedResetDate(
                observedResetAt: account.usageWindowResetAt,
                kind: .weekly,
                now: now
            )

            if let fiveHourDetection = detectUnexpectedEarlyReset(
                account: account,
                kind: .fiveHour,
                expectedResetAt: record.expectedFiveHourResetAt,
                observedResetAt: account.primaryUsageResetAt,
                previousUsageValue: record.lastSeenFiveHourUsagePercent,
                currentUsageValue: account.primaryUsagePercent,
                now: now,
                graceSeconds: graceSeconds
            ) {
                detections.append(fiveHourDetection)
            }
            record.expectedFiveHourResetAt = normalizedExpectedResetDate(
                observedResetAt: account.primaryUsageResetAt,
                kind: .fiveHour,
                now: now
            )

            record.lastSeenUsedUnits = account.usedUnits
            record.lastSeenFiveHourUsagePercent = account.primaryUsagePercent
            record.lastSeenAt = now
            recordsByKey[accountKey] = record
        }

        let activeAccountKeys = Set(paidAccounts.map(\.deduplicationKey))
        specialResetWatchState.records = recordsByKey
            .filter { activeAccountKeys.contains($0.key) }
            .map(\.value)
            .sorted(by: { $0.accountName.localizedCaseInsensitiveCompare($1.accountName) == .orderedAscending })
        specialResetWatchState.lastEvaluatedAt = now

        if !detections.isEmpty {
            let newEvents = detections.map { detection in
                SpecialResetEvent(
                    id: UUID(),
                    detectedAt: detection.detectedAt,
                    accountKey: detection.accountKey,
                    accountName: detection.accountName,
                    kind: detection.kind,
                    previousExpectedAt: detection.previousExpectedAt,
                    observedNextResetAt: detection.observedNextResetAt
                )
            }
            specialResetWatchState.events = Array((newEvents + specialResetWatchState.events).prefix(40))
            if specialResetWatchNotifyEnabled {
                postSpecialResetDetections(detections)
            }
        }

        persistSpecialResetWatchState()
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
        guard var observedResetAt else { return nil }
        var guardSteps = 0
        while observedResetAt <= now, guardSteps < 240 {
            observedResetAt = observedResetAt.addingTimeInterval(kind.interval)
            guardSteps += 1
        }
        return observedResetAt
    }

    private func detectUnexpectedEarlyReset(
        account: AgentAccount,
        kind: SpecialResetKind,
        expectedResetAt: Date?,
        observedResetAt: Date?,
        previousUsageValue: Int?,
        currentUsageValue: Int?,
        now: Date,
        graceSeconds: TimeInterval
    ) -> SpecialResetDetection? {
        guard let expectedResetAt,
              let observedNextResetAt = normalizedExpectedResetDate(
                observedResetAt: observedResetAt,
                kind: kind,
                now: now
              )
        else {
            return nil
        }

        let isNotDueYet = now.addingTimeInterval(graceSeconds) < expectedResetAt
        let shiftSeconds = abs(observedNextResetAt.timeIntervalSince(expectedResetAt))
        let isSignificantShift = shiftSeconds > max(600, graceSeconds / 2)
        let usageDropped = usageValueDropped(previousUsageValue: previousUsageValue, currentUsageValue: currentUsageValue)
        let hasStrongTimeSignal = expectedResetAt.timeIntervalSince(now) > max(900, graceSeconds)
        guard isNotDueYet, isSignificantShift, (usageDropped || hasStrongTimeSignal) else {
            return nil
        }

        return SpecialResetDetection(
            accountKey: account.deduplicationKey,
            accountName: normalizedSpecialResetAccountName(account),
            kind: kind,
            previousExpectedAt: expectedResetAt,
            observedNextResetAt: observedNextResetAt,
            detectedAt: now
        )
    }

    private func usageValueDropped(previousUsageValue: Int?, currentUsageValue: Int?) -> Bool {
        guard let previousUsageValue, let currentUsageValue else { return false }
        return currentUsageValue + 3 < previousUsageValue
    }

    private func normalizedSpecialResetAccountName(_ account: AgentAccount) -> String {
        let trimmed = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.text("account.unknown") : trimmed
    }

    private func postSpecialResetDetections(_ detections: [SpecialResetDetection]) {
        for detection in detections {
            let body = L10n.text(
                "special_reset.notification.body_format",
                "\(detection.accountName) · \(detection.kind.title)",
                specialResetDateText(detection.previousExpectedAt),
                specialResetDateText(detection.observedNextResetAt)
            )
            DesktopNotifier.post(
                key: "special-reset-\(detection.accountKey)-\(detection.kind.rawValue)-\(Int(detection.previousExpectedAt.timeIntervalSince1970))",
                title: L10n.text("special_reset.notification.title"),
                body: body,
                minInterval: 30
            )
        }
    }

    private func specialResetEventMessage(for event: SpecialResetEvent) -> String {
        L10n.text(
            "special_reset.event.message_format",
            "\(event.accountName) · \(event.kind.title)",
            specialResetDateText(event.previousExpectedAt),
            specialResetDateText(event.observedNextResetAt),
            specialResetDateText(event.detectedAt)
        )
    }

    private func specialResetDateText(_ date: Date) -> String {
        date.formatted(.dateTime.locale(L10n.locale()).month().day().hour().minute())
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

#Preview {
    PoolDashboardView(store: UserDefaultsAccountPoolStore(defaults: .standard, key: "preview_account_pool_snapshot"))
}
