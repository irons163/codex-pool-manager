import SwiftUI

struct PoolDashboardView: View {
    private static let codexAuthBookmarkKey = "codex_auth_json_bookmark"
    @AppStorage("oauth_issuer") private var oauthIssuer = "https://auth.openai.com"
    @AppStorage("oauth_client_id") private var oauthClientID = ""
    @AppStorage("oauth_scopes") private var oauthScopes = "openid profile email offline_access  api.connectors.read api.connectors.invoke"
    @AppStorage("oauth_redirect_uri") private var oauthRedirectURI = "http://localhost:1455/auth/callback"
    @AppStorage("oauth_originator") private var oauthOriginator = "codex_cli_rs"
    @AppStorage("oauth_workspace_id") private var oauthWorkspaceID = ""
    @State private var state: AccountPoolState
    @State private var formState = PoolDashboardFormState()
    @State private var resetAllLatch = DestructiveActionLatch()
    @State private var viewState = PoolDashboardViewState()
    @State private var lowUsageAlertPolicy = LowUsageAlertPolicy()
    @State private var localOAuthImportViewModel = LocalOAuthImportViewModel()
    @State private var sessionAuthorizedAuthFileURL: URL?
    private let store: AccountPoolStoring
    private let backupFlowCoordinator = PoolDashboardBackupFlowCoordinator()
    private let usageSyncFlowCoordinator = PoolDashboardUsageSyncFlowCoordinator()
    private let oauthSignInFlowCoordinator = PoolDashboardOAuthSignInFlowCoordinator()
    private let lifecycleFlowCoordinator = PoolDashboardLifecycleFlowCoordinator()
    private let accountFormFlowCoordinator = PoolDashboardAccountFormFlowCoordinator()
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

    init(store: AccountPoolStoring = UserDefaultsAccountPoolStore()) {
        self.store = store
        if let snapshot = store.load() {
            _state = State(initialValue: AccountPoolState(snapshot: snapshot))
        } else {
            var defaultState = AccountPoolState(
                accounts: [
                    AgentAccount(id: UUID(), name: "Codex-Team-A", usedUnits: 120, quota: PoolDashboardFormState.defaultQuota),
                    AgentAccount(id: UUID(), name: "Codex-Team-B", usedUnits: 460, quota: PoolDashboardFormState.defaultQuota),
                    AgentAccount(id: UUID(), name: "Codex-Team-C", usedUnits: 780, quota: PoolDashboardFormState.defaultQuota)
                ],
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

            ScrollView(showsIndicators: false) {
                GlassPanel {
                    dashboardContent
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minWidth: PoolDashboardTheme.minWidth, minHeight: PoolDashboardTheme.minHeight)
        .onAppear {
            handleOnAppear()
        }
        .onChange(of: state.snapshot) { _, snapshot in
            handleSnapshotChange(snapshot)
        }
        .alert("低剩餘用量提醒", isPresented: $viewState.showLowUsageAlert) {
            Button("知道了", role: .cancel) { }
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
        VStack(alignment: .leading, spacing: PoolDashboardTheme.sectionSpacing) {
            DashboardHeaderSectionView(
                accountCount: state.accounts.count,
                availableCount: state.availableAccountsCount,
                overallUsagePercent: Int(state.overallUsageRatio * 100),
                modeTitle: state.mode.rawValue
            )

            SyncToolbarView(
                isSyncing: viewState.isSyncingUsage,
                lastSyncAt: state.lastUsageSyncAt,
                errorText: viewState.syncError
            ) {
                Task { await syncCodexUsage() }
            }

            DebugToolsPanelView(
                showUsageRawJSON: $viewState.showUsageRawJSON,
                lastUsageRawJSON: $viewState.lastUsageRawJSON,
                showSwitchLaunchLog: $viewState.showSwitchLaunchLog,
                lastSwitchLaunchLog: $viewState.lastSwitchLaunchLog
            )

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

            StrategySettingsPanelView(
                mode: state.mode,
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

            OverallUsagePanelView(
                totalUsedUnits: state.totalUsedUnits,
                totalQuota: state.totalQuota,
                overallUsageRatio: state.overallUsageRatio,
                availableAccountsCount: state.availableAccountsCount,
                isPoolExhausted: state.isPoolExhausted,
                resetAllButtonTitle: resetAllLatch.isArmed ? "再次點擊確認重設全部" : "重設全部用量",
                onResetAll: {
                    handleResetAllUsage()
                }
            )

            ActiveAccountPanelView(
                activeAccount: state.activeAccount,
                mode: state.mode,
                isFocusLockActive: state.isFocusLockActive,
                hasLowUsageWarning: state.hasLowUsageWarning,
                lowUsageThresholdRatio: state.lowUsageThresholdRatio,
                onSimulateUsage: {
                    handleSimulateUsage()
                },
                onEvaluateSwitch: {
                    handleEvaluateSwitch()
                }
            )

            AccountUsagePanelView(
                newAccountName: $formState.newAccountName,
                newAccountQuota: $formState.newAccountQuota,
                accounts: state.accounts,
                onAddAccount: { name, quota in
                    handleAddAccount(name: name, quota: quota)
                },
                onSwitchAndLaunch: { account in
                    await switchAndLaunchCodex(using: account)
                },
                onRemoveAccount: { accountID in
                    handleRemoveAccount(accountID: accountID)
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
                usageSourceLabel: { account in
                    usagePresenter.usageSourceLabel(for: account)
                },
                usageWindowDetailLabel: { account in
                    usagePresenter.usageWindowDetailLabel(for: account)
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

            ActivityLogPanelView(
                activities: state.activities,
                onClearActivities: {
                    handleClearActivities()
                }
            )

            BackupRestorePanelView(
                backupJSON: $viewState.backupJSON,
                backupError: $viewState.backupError,
                onExport: exportSnapshot,
                onExportRefetchable: exportRefetchableSnapshot,
                onImport: importSnapshot
            )
        }
        .frame(maxWidth: PoolDashboardTheme.contentWidth, alignment: .leading)
        .padding(PoolDashboardTheme.panelPadding)
        .groupBoxStyle(DashboardGroupBoxStyle())
        .animation(.easeInOut(duration: 0.25), value: state.mode)
        .animation(.easeInOut(duration: 0.25), value: viewState.isSyncingUsage)
        .animation(.easeInOut(duration: 0.20), value: viewState.showUsageRawJSON)
        .animation(.easeInOut(duration: 0.20), value: viewState.showSwitchLaunchLog)
    }

    // MARK: - Lifecycle

    private func handleOnAppear() {
        let output = lifecycleFlowCoordinator.onAppear(
            state: state,
            lowUsageAlertPolicy: lowUsageAlertPolicy,
            viewModel: localOAuthImportViewModel,
            authFileAccessService: authFileAccessService,
            currentAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL
        )
        applyLifecycleOnAppearOutput(output)
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
        let output = accountFormFlowCoordinator.addAccount(
            from: state,
            formState: formState,
            name: name,
            quota: quota
        )
        state = output.state
        formState = output.formState
    }

    private func handleRemoveAccount(accountID: UUID) {
        applyQuickAction(.removeAccount(accountID))
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

        let output = await usageSyncFlowCoordinator.syncCodexUsage(
            from: state,
            viewState: viewState
        )
        applyUsageSyncOutput(output)
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
            currentAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL,
            authFileAccessService: authFileAccessService,
            viewModel: localOAuthImportViewModel,
            viewState: viewState,
            authorizeAuthFile: openAuthFilePanel
        )
        applySwitchLaunchOutput(output)
    }
}

#Preview {
    PoolDashboardView(store: UserDefaultsAccountPoolStore(defaults: .standard, key: "preview_account_pool_snapshot"))
        .preferredColorScheme(.dark)
}
