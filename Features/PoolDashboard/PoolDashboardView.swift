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
    private let backupCoordinator = PoolDashboardBackupCoordinator()
    private let runtimeCoordinator = PoolDashboardRuntimeCoordinator()
    private let lifecycleCoordinator = PoolDashboardLifecycleCoordinator()
    private let mutationCoordinator = PoolDashboardMutationCoordinator()
    private let actionCoordinator = PoolDashboardActionCoordinator()
    private let localAccountsCoordinator = PoolDashboardLocalAccountsCoordinator()
    private let localImportCoordinator = PoolDashboardLocalImportCoordinator()
    private let switchLaunchCoordinator = PoolDashboardSwitchLaunchCoordinator()
    private let usagePresenter = PoolAccountUsagePresenter()
    private let alertPresenter = PoolDashboardAlertPresenter()
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
                    AgentAccount(id: UUID(), name: "Codex-Team-A", usedUnits: 120, quota: 1000),
                    AgentAccount(id: UUID(), name: "Codex-Team-B", usedUnits: 460, quota: 1000),
                    AgentAccount(id: UUID(), name: "Codex-Team-C", usedUnits: 780, quota: 1000)
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

            ScrollView {
                GlassPanel {
                    VStack(alignment: .leading, spacing: 16) {
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
                    if resetAllLatch.confirmOrArm() {
                        actionCoordinator.resetAllUsage(state: &state)
                    }
                }
            )

            ActiveAccountPanelView(
                activeAccount: state.activeAccount,
                mode: state.mode,
                isFocusLockActive: state.isFocusLockActive,
                hasLowUsageWarning: state.hasLowUsageWarning,
                lowUsageThresholdRatio: state.lowUsageThresholdRatio,
                onSimulateUsage: {
                    actionCoordinator.simulateUsage(state: &state)
                },
                onEvaluateSwitch: {
                    actionCoordinator.evaluateSwitch(state: &state)
                }
            )

            AccountUsagePanelView(
                newAccountName: $formState.newAccountName,
                newAccountQuota: $formState.newAccountQuota,
                accounts: state.accounts,
                onAddAccount: { name, quota in
                    actionCoordinator.addAccount(state: &state, name: name, quota: quota)
                },
                onSwitchAndLaunch: { account in
                    await switchAndLaunchCodex(using: account)
                },
                onRemoveAccount: { accountID in
                    actionCoordinator.removeAccount(state: &state, accountID: accountID)
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
                    actionCoordinator.clearActivities(state: &state)
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
                .padding(20)
            }
        }
        }
        .frame(minWidth: PoolDashboardTheme.minWidth, minHeight: PoolDashboardTheme.minHeight)
        .onAppear {
            lifecycleCoordinator.onAppear(
                state: &state,
                lowUsageAlertPolicy: &lowUsageAlertPolicy
            )
            refreshLocalOAuthAccounts()
        }
        .onChange(of: state.snapshot) { _, snapshot in
            store.save(snapshot)
            if lifecycleCoordinator.shouldShowLowUsageAlert(
                state: state,
                lowUsageAlertPolicy: &lowUsageAlertPolicy
            ) {
                viewState.showLowUsageAlert = true
            }
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

    private func exportSnapshot() {
        let result = backupCoordinator.exportSnapshot(from: state.snapshot)
        if let json = result.json {
            viewState.backupJSON = json
            viewState.backupError = nil
        } else if let message = result.errorMessage {
            viewState.backupError = message
        }
    }

    private func exportRefetchableSnapshot() {
        let result = backupCoordinator.exportRefetchableSnapshot(from: state.snapshot)
        if let json = result.json {
            viewState.backupJSON = json
            viewState.backupError = nil
        } else if let message = result.errorMessage {
            viewState.backupError = message
        }
    }

    private func importSnapshot() {
        let result = backupCoordinator.importSnapshotState(from: viewState.backupJSON)
        if let importedState = result.state {
            state = importedState
            viewState.backupError = nil
            Task { await syncCodexUsage() }
        } else if let message = result.errorMessage {
            viewState.backupError = message
        }
    }

    private var intelligentCandidateName: String? {
        guard let candidateID = state.intelligentCandidateID else { return nil }
        return state.accounts.first(where: { $0.id == candidateID })?.name
    }

    @MainActor
    private func syncCodexUsage() async {
        guard !viewState.isSyncingUsage else { return }
        viewState.isSyncingUsage = true
        defer { viewState.isSyncingUsage = false }

        let output = await runtimeCoordinator.syncCodexUsage(from: state)
        mutationCoordinator.applySyncOutput(
            output,
            state: &state,
            viewState: &viewState
        )
    }

    @MainActor
    private func signInWithOAuth() async {
        guard !viewState.isSigningInOAuth else { return }
        viewState.isSigningInOAuth = true
        defer { viewState.isSigningInOAuth = false }

        viewState.oauthError = nil
        viewState.oauthSuccessMessage = nil

        let output = await runtimeCoordinator.signInWithOAuth(
            from: state,
            input: .init(
                issuer: oauthIssuer,
                clientID: oauthClientID,
                scopes: oauthScopes,
                redirectURI: oauthRedirectURI,
                originator: oauthOriginator,
                workspaceID: oauthWorkspaceID,
                accountNameInput: formState.oauthAccountName,
                fallbackQuota: formState.oauthAccountQuota
            )
        )
        let shouldRefresh = mutationCoordinator.applyOAuthOutput(
            output,
            state: &state,
            viewState: &viewState,
            oauthAccountName: &formState.oauthAccountName
        )
        if shouldRefresh {
            refreshLocalOAuthAccounts()
        }
    }

    private func refreshLocalOAuthAccounts() {
        sessionAuthorizedAuthFileURL = localAccountsCoordinator.refreshLocalOAuthAccounts(
            state: &state,
            viewModel: &localOAuthImportViewModel,
            authFileAccessService: authFileAccessService,
            currentAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL
        )
    }

    @MainActor
    @discardableResult
    private func openAuthFilePanel() -> URL? {
        guard let url = localAccountsCoordinator.openAuthFilePanelAndLoad(
            state: &state,
            viewModel: &localOAuthImportViewModel,
            authFileAccessService: authFileAccessService
        ) else {
            return nil
        }
        sessionAuthorizedAuthFileURL = url
        return url
    }

    @MainActor
    private func importLocalOAuthAccount(_ localAccount: LocalCodexOAuthAccount) async {
        let output = await localImportCoordinator.importLocalOAuthAccount(
            localAccount,
            state: state,
            viewModel: localOAuthImportViewModel,
            onRawResponse: { raw in
                viewState.lastUsageRawJSON = raw
            }
        )
        mutationCoordinator.applyLocalImportOutput(
            output,
            state: &state,
            viewModel: &localOAuthImportViewModel,
            viewState: &viewState
        )
    }

    @MainActor
    private func switchAndLaunchCodex(using account: AgentAccount) async {
        let output = await switchLaunchCoordinator.switchAndLaunch(
            account: account,
            currentAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL,
            authFileAccessService: authFileAccessService,
            authorizeAuthFile: {
                openAuthFilePanel()
            }
        )
        mutationCoordinator.applySwitchOutput(
            output,
            viewModel: &localOAuthImportViewModel,
            viewState: &viewState,
            sessionAuthorizedAuthFileURL: &sessionAuthorizedAuthFileURL
        )
    }
}

#Preview {
    PoolDashboardView(store: UserDefaultsAccountPoolStore(defaults: .standard, key: "preview_account_pool_snapshot"))
}
