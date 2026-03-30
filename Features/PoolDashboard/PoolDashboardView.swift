import SwiftUI

struct PoolDashboardView: View {
    private static let codexAuthBookmarkKey = "codex_auth_json_bookmark"
    private static let defaultOAuthClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    @AppStorage("oauth_issuer") private var oauthIssuer = "https://auth.openai.com"
    @AppStorage("oauth_client_id") private var oauthClientID = Self.defaultOAuthClientID
    @AppStorage("oauth_scopes") private var oauthScopes = "openid profile email offline_access  api.connectors.read api.connectors.invoke"
    @AppStorage("oauth_redirect_uri") private var oauthRedirectURI = "http://localhost:1455/auth/callback"
    @AppStorage("oauth_originator") private var oauthOriginator = "codex_cli_rs"
    @AppStorage("oauth_workspace_id") private var oauthWorkspaceID = ""
    @AppStorage(L10n.languageOverrideKey) private var appLanguageOverride = L10n.systemLanguageCode
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
    @State private var suppressNextSnapshotDrivenSwitch = false
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
        [
            AgentAccount(id: UUID(), name: "Codex-Team-A", usedUnits: 120, quota: PoolDashboardFormState.defaultQuota),
            AgentAccount(id: UUID(), name: "Codex-Team-B", usedUnits: 460, quota: PoolDashboardFormState.defaultQuota),
            AgentAccount(id: UUID(), name: "Codex-Team-C", usedUnits: 780, quota: PoolDashboardFormState.defaultQuota)
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
        case settings
        case safety
        case developer

        var id: String { rawValue }

        var title: String {
            switch self {
            case .authentication: L10n.text("workspace.authentication.title")
            case .runtime: L10n.text("workspace.runtime.title")
            case .settings: L10n.text("workspace.settings.title")
            case .safety: L10n.text("workspace.safety.title")
            case .developer: L10n.text("workspace.developer.title")
            }
        }

        var subtitle: String {
            switch self {
            case .authentication: L10n.text("workspace.authentication.subtitle")
            case .runtime: L10n.text("workspace.runtime.subtitle")
            case .settings: L10n.text("workspace.settings.subtitle")
            case .safety: L10n.text("workspace.safety.subtitle")
            case .developer: L10n.text("workspace.developer.subtitle")
            }
        }

        var symbolName: String {
            switch self {
            case .authentication: "person.badge.key"
            case .runtime: "dial.medium"
            case .settings: "gearshape"
            case .safety: "shield.lefthalf.filled.badge.checkmark"
            case .developer: "wrench.and.screwdriver"
            }
        }
    }

    init(store: AccountPoolStoring = UserDefaultsAccountPoolStore()) {
        self.store = store
        if let snapshot = store.load() {
            _state = State(initialValue: AccountPoolState(snapshot: snapshot))
        } else {
            var defaultState = AccountPoolState(
                accounts: Self.defaultAccounts,
                mode: .intelligent,
                minSwitchInterval: 300,
                lowUsageThresholdRatio: 0.15
            )
            defaultState.evaluate(now: .now)
            _state = State(initialValue: defaultState)
        }
    }

    var body: some View {
        ZStack {
            PoolDashboardTheme.backgroundGradient
                .ignoresSafeArea()
            Circle()
                .fill(PoolDashboardTheme.glowA.opacity(0.30))
                .frame(width: PoolDashboardTheme.glowLargeSize, height: PoolDashboardTheme.glowLargeSize)
                .blur(radius: PoolDashboardTheme.glowLargeBlur)
                .offset(x: -300, y: -260)
                .allowsHitTesting(false)
            Circle()
                .fill(PoolDashboardTheme.glowB.opacity(0.22))
                .frame(width: PoolDashboardTheme.glowMediumSize, height: PoolDashboardTheme.glowMediumSize)
                .blur(radius: PoolDashboardTheme.glowMediumBlur)
                .offset(x: 340, y: 220)
                .allowsHitTesting(false)
            Rectangle()
                .fill(
                    RadialGradient(
                        colors: [.clear, Color.black.opacity(0.24)],
                        center: .center,
                        startRadius: 120,
                        endRadius: 920
                    )
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

            dashboardContent
        }
        .frame(minWidth: PoolDashboardTheme.minWidth, minHeight: PoolDashboardTheme.minHeight)
        .onAppear {
            handleOnAppear()
        }
        .onChange(of: state.snapshot) { previousSnapshot, snapshot in
            handleSnapshotChange(snapshot)
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
        .onChange(of: state.groups) { _, groups in
            if groups.isEmpty {
                selectedGroupName = AgentAccount.defaultGroupName
            } else if !groups.contains(where: { $0.caseInsensitiveCompare(selectedGroupName) == .orderedSame }) {
                selectedGroupName = groups[0]
            }
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
            Button(L10n.text("alert.dismiss"), role: .cancel) { }
        } message: {
            Text(
                alertPresenter.lowUsageAlertMessage(
                    activeAccount: state.activeAccount,
                    thresholdRatio: state.lowUsageThresholdRatio
                )
            )
        }
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
                                accountCount: state.accounts.count,
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
                        PoolDashboardTheme.panelStrongFill.opacity(0.82)
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
        .background(PoolDashboardTheme.panelStrongFill.opacity(0.52))
        .groupBoxStyle(DashboardGroupBoxStyle())
        .animation(.easeInOut(duration: PoolDashboardTheme.standardAnimationDuration), value: state.mode)
        .animation(.easeInOut(duration: PoolDashboardTheme.standardAnimationDuration), value: viewState.isSyncingUsage)
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
        .background(PoolDashboardTheme.panelMutedFill.opacity(0.72))
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
            .background(PoolDashboardTheme.panelStrongFill.opacity(0.78))
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
                .fill(PoolDashboardTheme.panelMutedFill.opacity(0.45))
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
        .background(PoolDashboardTheme.panelMutedFill.opacity(0.72))
    }

    private var visibleWorkspaces: [Workspace] {
        Workspace.allCases.filter { workspace in
            if workspace == .developer {
                return isDeveloperBuild
            }
            return true
        }
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
        case .runtime, .settings:
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
        case .settings:
            EmptyView()
        case .safety:
            safetyContextPanel
        case .developer:
            developerContextPanel
        }
    }

    private var safetyContextPanel: some View {
        GroupBox(L10n.text("safety.signals.title")) {
            VStack(alignment: .leading, spacing: 10) {
                PanelStatusCalloutView(
                    message: L10n.text("safety.operational.message"),
                    title: L10n.text("safety.operational.title"),
                    tone: .info
                )

                if isDeveloperBuild {
                    Text(L10n.text("safety.developer_available"))
                        .font(.footnote)
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                        .dashboardInfoCard()
                }
            }
        }
        .sectionCardStyle()
    }

    private var developerContextPanel: some View {
        GroupBox(L10n.text("developer.diagnostics.title")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("developer.diagnostics.subtitle"))
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                activityLogPanel
            }
        }
        .sectionCardStyle()
    }

    private func workspaceButton(for workspace: Workspace) -> some View {
        Button {
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
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: PoolDashboardTheme.workspaceSidebarItemCornerRadius, style: .continuous)
                    .fill(selectedWorkspace == workspace ? PoolDashboardTheme.panelStrongFill : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.workspaceSidebarItemCornerRadius, style: .continuous)
                            .stroke(
                                selectedWorkspace == workspace ? PoolDashboardTheme.glowA.opacity(0.5) : PoolDashboardTheme.panelInnerStroke,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedWorkspace == workspace ? PoolDashboardTheme.textPrimary : PoolDashboardTheme.textSecondary)
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
            isSigningInOAuth: viewState.isSigningInOAuth,
            oauthSuccessMessage: viewState.oauthSuccessMessage,
            oauthError: viewState.oauthError,
            onSignIn: {
                await signInWithOAuth()
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
            intelligentCandidateName: intelligentCandidateName,
            canIntelligentSwitch: state.canIntelligentSwitch(),
            intelligentCooldownRemaining: state.intelligentSwitchCooldownRemaining(),
            modeBinding: strategyBindings.mode,
            manualSelectionBinding: strategyBindings.manualSelection,
            minSwitchIntervalBinding: strategyBindings.minSwitchInterval,
            lowThresholdBinding: strategyBindings.lowThreshold,
            minUsageDeltaBinding: strategyBindings.minUsageDelta
        )
    }

    private var workspaceSettingsPanel: some View {
        WorkspaceSettingsPanelView(
            switchWithoutLaunchingBinding: strategyBindings.switchWithoutLaunching,
            autoSyncEnabledBinding: strategyBindings.autoSyncEnabled,
            autoSyncIntervalSecondsBinding: strategyBindings.autoSyncIntervalSeconds,
            languageOverrideBinding: $appLanguageOverride,
            languageOptions: L10n.languageOptions
        )
    }

    private var activeAccountPanel: some View {
        ActiveAccountPanelView(
            activeAccount: state.activeAccount,
            mode: state.mode,
            isFocusLockActive: state.isFocusLockActive,
            hasLowUsageWarning: state.hasLowUsageWarning,
            lowUsageThresholdRatio: state.lowUsageThresholdRatio,
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

        let output = lifecycleFlowCoordinator.onAppear(
            state: state,
            lowUsageAlertPolicy: lowUsageAlertPolicy,
            viewModel: localOAuthImportViewModel,
            authFileAccessService: authFileAccessService,
            currentAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL
        )
        applyLifecycleOnAppearOutput(output)
    }

    private func migrateDefaultOAuthClientIDIfNeeded() {
        guard oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        oauthClientID = Self.defaultOAuthClientID
    }

    private func handleSnapshotChange(_ snapshot: AccountPoolSnapshot) {
        let output = lifecycleFlowCoordinator.onSnapshotChanged(
            snapshot: snapshot,
            state: state,
            lowUsageAlertPolicy: lowUsageAlertPolicy,
            viewState: viewState,
            store: store
        )
        applyLifecycleSnapshotChangeOutput(output)
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
        defer { asyncStateCoordinator.endUsageSync(viewState: &viewState) }

        let previousMode = state.mode
        let previousActiveAccountID = state.activeAccountID

        let output = await usageSyncFlowCoordinator.syncCodexUsage(
            from: state,
            viewState: viewState
        )
        applyUsageSyncOutput(output)

        await triggerAutomaticSwitchActionIfNeeded(
            previousMode: previousMode,
            previousActiveAccountID: previousActiveAccountID
        )
    }

    // MARK: - OAuth

    @MainActor
    private func signInWithOAuth() async {
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
        applyOAuthSignInOutput(output)
        if output.shouldRefreshLocalOAuthAccounts {
            refreshLocalOAuthAccounts()
        }
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
        } else if let previousActiveAccountID,
                  state.accounts.contains(where: { $0.id == previousActiveAccountID }) {
            suppressNextSnapshotDrivenSwitch = true
            state.markActiveAccountForSwitchLaunch(previousActiveAccountID)
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
        }
        applySwitchLaunchOutput(output)
    }
}

#Preview {
    PoolDashboardView(store: UserDefaultsAccountPoolStore(defaults: .standard, key: "preview_account_pool_snapshot"))
        .preferredColorScheme(.dark)
}
