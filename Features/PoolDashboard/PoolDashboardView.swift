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
    @State private var newAccountName = ""
    @State private var newAccountQuota = 1000
    @State private var oauthAccountName = ""
    @State private var oauthAccountQuota = 1000
    @State private var resetAllLatch = DestructiveActionLatch()
    @State private var backupJSON = ""
    @State private var backupError: String?
    @State private var showLowUsageAlert = false
    @State private var lowUsageAlertPolicy = LowUsageAlertPolicy()
    @State private var isSyncingUsage = false
    @State private var syncError: String?
    @State private var lastUsageRawJSON = ""
    @State private var showUsageRawJSON = false
    @State private var lastSwitchLaunchLog = ""
    @State private var showSwitchLaunchLog = false
    @State private var isSigningInOAuth = false
    @State private var oauthError: String?
    @State private var oauthSuccessMessage: String?
    @State private var localOAuthImportViewModel = LocalOAuthImportViewModel()
    @State private var sessionAuthorizedAuthFileURL: URL?
    private let store: AccountPoolStoring
    private let dataFlowCoordinator = PoolDashboardDataFlowCoordinator()
    private let runtimeCoordinator = PoolDashboardRuntimeCoordinator()
    private let localAccountsCoordinator = PoolDashboardLocalAccountsCoordinator()
    private let localImportCoordinator = PoolDashboardLocalImportCoordinator()
    private let switchLaunchCoordinator = PoolDashboardSwitchLaunchCoordinator()
    private let usagePresenter = PoolAccountUsagePresenter()
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
                    isSyncing: isSyncingUsage,
                    lastSyncAt: state.lastUsageSyncAt,
                    errorText: syncError
                ) {
                    Task { await syncCodexUsage() }
                }

            DebugToolsPanelView(
                showUsageRawJSON: $showUsageRawJSON,
                lastUsageRawJSON: $lastUsageRawJSON,
                showSwitchLaunchLog: $showSwitchLaunchLog,
                lastSwitchLaunchLog: $lastSwitchLaunchLog
            )

            OAuthLoginPanelView(
                oauthIssuer: $oauthIssuer,
                oauthClientID: $oauthClientID,
                oauthScopes: $oauthScopes,
                oauthRedirectURI: $oauthRedirectURI,
                oauthOriginator: $oauthOriginator,
                oauthWorkspaceID: $oauthWorkspaceID,
                oauthAccountName: $oauthAccountName,
                oauthAccountQuota: $oauthAccountQuota,
                isSigningInOAuth: isSigningInOAuth,
                oauthSuccessMessage: oauthSuccessMessage,
                oauthError: oauthError,
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
                        state.resetAllUsage()
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
                    state.recordUsage(units: 50)
                },
                onEvaluateSwitch: {
                    state.evaluate()
                }
            )

            AccountUsagePanelView(
                newAccountName: $newAccountName,
                newAccountQuota: $newAccountQuota,
                accounts: state.accounts,
                onAddAccount: { name, quota in
                    state.addAccount(name: name, quota: quota)
                },
                onSwitchAndLaunch: { account in
                    await switchAndLaunchCodex(using: account)
                },
                onRemoveAccount: { accountID in
                    state.removeAccount(accountID)
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
                    state.clearActivities()
                }
            )

            BackupRestorePanelView(
                backupJSON: $backupJSON,
                backupError: $backupError,
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
            state.evaluate()
            _ = lowUsageAlertPolicy.shouldTriggerAlert(mode: state.mode, hasLowUsageWarning: state.hasLowUsageWarning)
            refreshLocalOAuthAccounts()
        }
        .onChange(of: state.snapshot) { _, snapshot in
            store.save(snapshot)
            if lowUsageAlertPolicy.shouldTriggerAlert(mode: state.mode, hasLowUsageWarning: state.hasLowUsageWarning) {
                showLowUsageAlert = true
            }
        }
        .alert("低剩餘用量提醒", isPresented: $showLowUsageAlert) {
            Button("知道了", role: .cancel) { }
        } message: {
            if let active = state.activeAccount {
                Text("\(active.name) 剩餘 \(active.remainingUnits)，已低於 \(Int(state.lowUsageThresholdRatio * 100))% 門檻。")
            } else {
                Text("目前帳號剩餘用量偏低。")
            }
        }
    }

    private func exportSnapshot() {
        do {
            backupJSON = try dataFlowCoordinator.exportSnapshotJSON(state.snapshot)
            backupError = nil
        } catch {
            backupError = "匯出失敗：\(error.localizedDescription)"
        }
    }

    private func exportRefetchableSnapshot() {
        do {
            backupJSON = try dataFlowCoordinator.exportRefetchableSnapshotJSON(state.snapshot)
            backupError = nil
        } catch {
            backupError = "匯出失敗：\(error.localizedDescription)"
        }
    }

    private func importSnapshot() {
        do {
            state = try dataFlowCoordinator.importState(from: backupJSON)
            backupError = nil
            Task { await syncCodexUsage() }
        } catch {
            backupError = "匯入失敗：\(error.localizedDescription)"
        }
    }

    private var intelligentCandidateName: String? {
        guard let candidateID = state.intelligentCandidateID else { return nil }
        return state.accounts.first(where: { $0.id == candidateID })?.name
    }

    @MainActor
    private func syncCodexUsage() async {
        guard !isSyncingUsage else { return }
        isSyncingUsage = true
        defer { isSyncingUsage = false }

        let output = await runtimeCoordinator.syncCodexUsage(from: state)
        state = output.state
        if let rawResponse = output.lastUsageRawJSON {
            lastUsageRawJSON = rawResponse
        }
        syncError = output.syncError
    }

    @MainActor
    private func signInWithOAuth() async {
        guard !isSigningInOAuth else { return }
        isSigningInOAuth = true
        defer { isSigningInOAuth = false }

        oauthError = nil
        oauthSuccessMessage = nil

        let output = await runtimeCoordinator.signInWithOAuth(
            from: state,
            input: .init(
                issuer: oauthIssuer,
                clientID: oauthClientID,
                scopes: oauthScopes,
                redirectURI: oauthRedirectURI,
                originator: oauthOriginator,
                workspaceID: oauthWorkspaceID,
                accountNameInput: oauthAccountName,
                fallbackQuota: oauthAccountQuota
            )
        )
        state = output.state
        oauthError = output.oauthError
        oauthSuccessMessage = output.oauthSuccessMessage
        oauthAccountName = output.nextOAuthAccountName
        if output.shouldRefreshLocalOAuthAccounts {
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

    private func loadLocalOAuthAccounts(from url: URL) {
        sessionAuthorizedAuthFileURL = url
        localAccountsCoordinator.loadLocalOAuthAccounts(
            from: url,
            state: &state,
            viewModel: &localOAuthImportViewModel,
            authFileAccessService: authFileAccessService
        )
    }

    private func saveAuthFileBookmark(for url: URL) {
        localAccountsCoordinator.saveAuthFileBookmark(
            for: url,
            viewModel: &localOAuthImportViewModel,
            authFileAccessService: authFileAccessService
        )
    }

    @discardableResult
    private func loadLocalOAuthAccountsFromBookmark() -> Bool {
        let result = localAccountsCoordinator.loadLocalOAuthAccountsFromBookmark(
            state: &state,
            viewModel: &localOAuthImportViewModel,
            authFileAccessService: authFileAccessService,
            currentAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL
        )
        sessionAuthorizedAuthFileURL = result.authorizedURL
        return result.didLoadAccounts
    }

    private func hasSavedAuthFileBookmark() -> Bool {
        localAccountsCoordinator.hasSavedAuthFileBookmark(authFileAccessService: authFileAccessService)
    }

    @MainActor
    @discardableResult
    private func openAuthFilePanel() -> URL? {
        guard let url = CodexAuthFilePanelService().pickAuthFileURL() else {
#if !canImport(AppKit)
            localOAuthImportViewModel.errorMessage = "目前平台不支援檔案面板"
#endif
            return nil
        }

        saveAuthFileBookmark(for: url)
        loadLocalOAuthAccounts(from: url)
        return url
    }

    @MainActor
    private func importLocalOAuthAccount(_ localAccount: LocalCodexOAuthAccount) async {
        let output = await localImportCoordinator.importLocalOAuthAccount(
            localAccount,
            state: state,
            viewModel: localOAuthImportViewModel,
            onRawResponse: { raw in
                lastUsageRawJSON = raw
            }
        )
        state = output.state
        localOAuthImportViewModel = output.viewModel
        if output.didImport {
            syncError = nil
        }
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
        lastSwitchLaunchLog = output.switchLaunchLog
        localOAuthImportViewModel.errorMessage = output.errorMessage
        sessionAuthorizedAuthFileURL = output.sessionAuthorizedAuthFileURL
    }
}

#Preview {
    PoolDashboardView(store: UserDefaultsAccountPoolStore(defaults: .standard, key: "preview_account_pool_snapshot"))
}
