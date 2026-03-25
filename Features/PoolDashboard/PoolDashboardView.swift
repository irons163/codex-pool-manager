import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

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
    private let authFlowCoordinator = PoolDashboardAuthFlowCoordinator()
    private let dataFlowCoordinator = PoolDashboardDataFlowCoordinator()

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

            GroupBox("OAuth 登入（你自行填 client_id）") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Client ID", text: $oauthClientID)
                        .textFieldStyle(.roundedBorder)

                    DisclosureGroup("進階設定（一般情況不用改）") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Issuer (例如 https://auth.openai.com)", text: $oauthIssuer)
                                .textFieldStyle(.roundedBorder)
                            TextField("Scopes", text: $oauthScopes)
                                .textFieldStyle(.roundedBorder)
                            TextField("Redirect URI", text: $oauthRedirectURI)
                                .textFieldStyle(.roundedBorder)
                            TextField("Originator", text: $oauthOriginator)
                                .textFieldStyle(.roundedBorder)
                            TextField("Allowed Workspace ID（可留空）", text: $oauthWorkspaceID)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.top, 4)
                    }

                    HStack {
                        TextField("登入後帳號名稱", text: $oauthAccountName)
                            .textFieldStyle(.roundedBorder)
                        Stepper("配額 \(oauthAccountQuota)", value: $oauthAccountQuota, in: 100...20_000, step: 100)
                    }

                    HStack {
                        Button(isSigningInOAuth ? "OAuth 登入中..." : "OAuth 登入並新增帳號") {
                            Task { await signInWithOAuth() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSigningInOAuth)

                        if let oauthSuccessMessage {
                            Text(oauthSuccessMessage)
                                .font(.footnote)
                                .foregroundStyle(.green)
                        }
                        if let oauthError {
                            Text(oauthError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            GroupBox("本機已登入 OAuth 帳號") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button("掃描本機登入") {
                            refreshLocalOAuthAccounts()
                        }
                        .buttonStyle(.bordered)

                        Button("選擇 auth.json") {
                            openAuthFilePanel()
                        }
                        .buttonStyle(.bordered)

                        if let localOAuthError = localOAuthImportViewModel.errorMessage {
                            Text(localOAuthError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        } else {
                            Text("找到 \(localOAuthImportViewModel.accounts.count) 個帳號")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if localOAuthImportViewModel.accounts.isEmpty {
                        Text("尚未找到本機 OAuth 帳號。若你已登入 Codex，請點「選擇 auth.json」並選擇 ~/.codex/auth.json")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(localOAuthImportViewModel.accounts) { account in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.displayName)
                                    if let email = account.email {
                                        Text(email)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(account.maskedToken)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    if let chatGPTAccountID = account.chatGPTAccountID {
                                        Text("Account ID: \(chatGPTAccountID)")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("缺少 Account ID，無法查詢用量")
                                            .font(.footnote)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                                Button("匯入") {
                                    Task {
                                        await importLocalOAuthAccount(account)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(account.chatGPTAccountID == nil)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            Picker("切換模式", selection: modeBinding) {
                ForEach(SwitchMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            GroupBox("策略設定") {
                VStack(alignment: .leading, spacing: 10) {
                    Stepper(
                        "最小切換間隔 \(Int(state.minSwitchInterval)) 秒",
                        value: minSwitchIntervalBinding,
                        in: 30...1800,
                        step: 30
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        Text("低用量提醒門檻 \(Int(state.lowUsageThresholdRatio * 100))%")
                        Slider(value: lowThresholdBinding, in: 0.05...0.5, step: 0.01)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("智能切換最小改善 \(Int(state.minUsageRatioDeltaToSwitch * 100))%")
                        Slider(value: minUsageDeltaBinding, in: 0...0.2, step: 0.01)
                    }
                    if state.mode == .intelligent {
                        if let candidateID = state.intelligentCandidateID,
                           let candidate = state.accounts.first(where: { $0.id == candidateID }) {
                            Text("推薦切換帳號：\(candidate.name)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if state.canIntelligentSwitch() {
                            Text("目前可切換帳號")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        } else {
                            Text("冷卻中，\(state.intelligentSwitchCooldownRemaining()) 秒後可切換")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            GroupBox("整體用量") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("總用量 \(state.totalUsedUnits)/\(state.totalQuota)")
                        Spacer()
                        Text("\(Int(state.overallUsageRatio * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: state.overallUsageRatio)
                    Button(resetAllLatch.isArmed ? "再次點擊確認重設全部" : "重設全部用量") {
                        if resetAllLatch.confirmOrArm() {
                            state.resetAllUsage()
                        }
                    }
                    .buttonStyle(.bordered)
                    HStack {
                        Text("可用帳號數 \(state.availableAccountsCount)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    if state.isPoolExhausted {
                        Text("所有帳號用量已耗盡，請補充配額或重設用量。")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
            }

            if state.mode == .manual, !state.accounts.isEmpty {
                Picker("手動帳號", selection: manualSelectionBinding) {
                    ForEach(state.accounts) { account in
                        Text(account.name).tag(account.id)
                    }
                }
            }

            GroupBox("目前使用帳號") {
                VStack(alignment: .leading, spacing: 8) {
                    if let active = state.activeAccount {
                        HStack {
                            Text(active.name)
                                .font(.headline)
                            Spacer()
                            Text("剩餘 \(active.remainingUnits)")
                                .font(.headline)
                        }

                        ProgressView(value: active.usageRatio)

                        if state.isFocusLockActive {
                            Text("專注模式鎖定中")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                        }

                        if state.mode == .focus && state.hasLowUsageWarning {
                            Text("低剩餘用量提醒：目前帳號剩餘不足 \(Int(state.lowUsageThresholdRatio * 100))%")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }

                        HStack {
                            Button("模擬使用 +50") {
                                state.recordUsage(units: 50)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("重新評估切換") {
                                state.evaluate()
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        Text("目前沒有可用帳號")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("帳號用量") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField("新帳號名稱", text: $newAccountName)
                            .textFieldStyle(.roundedBorder)
                        Stepper("配額 \(newAccountQuota)", value: $newAccountQuota, in: 100...10_000, step: 100)
                        Button("新增帳號") {
                            state.addAccount(name: newAccountName.trimmingCharacters(in: .whitespacesAndNewlines), quota: newAccountQuota)
                            newAccountName = ""
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    List {
                        ForEach(state.accounts) { account in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        TextField("帳號名稱", text: accountNameBinding(accountID: account.id))
                                            .textFieldStyle(.roundedBorder)
                                        if let chatGPTAccountID = account.chatGPTAccountID {
                                            Text("Account ID: \(chatGPTAccountID)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(usageSourceLabel(for: account))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if let usageWindowDetail = usageWindowDetailLabel(for: account) {
                                            Text(usageWindowDetail)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Button("切換並啟動") {
                                        Task {
                                            await switchAndLaunchCodex(using: account)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    Button("刪除", role: .destructive) {
                                        state.removeAccount(account.id)
                                    }
                                }

                                if isPercentUsageAccount(account) {
                                    HStack {
                                        Text("已用 \(account.usedUnits)%")
                                        Spacer()
                                        Text("剩餘 \(account.remainingUnits)%")
                                    }
                                    .font(.subheadline)
                                } else {
                                    HStack {
                                        Stepper(
                                            "已用 \(account.usedUnits)",
                                            value: accountUsedBinding(accountID: account.id),
                                            in: 0...account.quota,
                                            step: 50
                                        )
                                        Stepper(
                                            "配額 \(account.quota)",
                                            value: accountQuotaBinding(accountID: account.id),
                                            in: 100...20_000,
                                            step: 100
                                        )
                                    }
                                }

                                HStack {
                                    Text(remainingLabel(for: account))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(Int(account.usageRatio * 100))%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                ProgressView(value: account.usageRatio)
                                    .tint(usageProgressColor(for: account))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 220)
                }
            }

            GroupBox("近期活動") {
                if state.activities.isEmpty {
                    Text("目前沒有活動紀錄")
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Spacer()
                        Button("清除活動紀錄", role: .destructive) {
                            state.clearActivities()
                        }
                        .buttonStyle(.bordered)
                    }
                    List(state.activities.prefix(8)) { activity in
                        HStack {
                            Text(activity.timestamp, format: Date.FormatStyle(date: .omitted, time: .standard))
                                .foregroundStyle(.secondary)
                            Text(activity.message)
                        }
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 160)
                }
            }

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

    private var modeBinding: Binding<SwitchMode> {
        Binding(
            get: { state.mode },
            set: { newMode in
                state.setMode(newMode)
            }
        )
    }

    private var manualSelectionBinding: Binding<UUID> {
        Binding(
            get: {
                if let manualID = state.manualAccountID {
                    return manualID
                }
                return state.accounts.first?.id ?? UUID()
            },
            set: { newID in
                state.selectManualAccount(newID)
            }
        )
    }

    private var minSwitchIntervalBinding: Binding<Double> {
        Binding(
            get: { state.minSwitchInterval },
            set: { newValue in
                state.updateSwitchSettings(minSwitchInterval: newValue)
            }
        )
    }

    private var lowThresholdBinding: Binding<Double> {
        Binding(
            get: { state.lowUsageThresholdRatio },
            set: { newValue in
                state.updateSwitchSettings(lowUsageThresholdRatio: newValue)
            }
        )
    }

    private var minUsageDeltaBinding: Binding<Double> {
        Binding(
            get: { state.minUsageRatioDeltaToSwitch },
            set: { newValue in
                state.updateSwitchSettings(minUsageRatioDeltaToSwitch: newValue)
            }
        )
    }

    private func accountNameBinding(accountID: UUID) -> Binding<String> {
        Binding(
            get: {
                state.accounts.first(where: { $0.id == accountID })?.name ?? ""
            },
            set: { newName in
                state.updateAccount(accountID, name: newName)
            }
        )
    }

    private func accountQuotaBinding(accountID: UUID) -> Binding<Int> {
        Binding(
            get: {
                state.accounts.first(where: { $0.id == accountID })?.quota ?? 100
            },
            set: { newQuota in
                state.updateAccount(accountID, quota: newQuota)
            }
        )
    }

    private func accountUsedBinding(accountID: UUID) -> Binding<Int> {
        Binding(
            get: {
                state.accounts.first(where: { $0.id == accountID })?.usedUnits ?? 0
            },
            set: { newUsed in
                state.updateAccount(accountID, usedUnits: newUsed)
            }
        )
    }

    @MainActor
    private func syncCodexUsage() async {
        guard !isSyncingUsage else { return }
        isSyncingUsage = true
        defer { isSyncingUsage = false }

        do {
            let result = try await dataFlowCoordinator.syncState(from: state)
            state = result.state
            if let rawResponse = result.rawResponse {
                lastUsageRawJSON = rawResponse
            }
            syncError = nil
        } catch {
            syncError = "同步失敗：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func signInWithOAuth() async {
        guard !isSigningInOAuth else { return }
        isSigningInOAuth = true
        defer { isSigningInOAuth = false }

        oauthError = nil
        oauthSuccessMessage = nil

        do {
            let configuration = try authFlowCoordinator.buildConfiguration(
                issuer: oauthIssuer,
                clientID: oauthClientID,
                scopes: oauthScopes,
                redirectURI: oauthRedirectURI,
                originator: oauthOriginator,
                workspaceID: oauthWorkspaceID
            )

            let context = try await authFlowCoordinator.fetchOAuthSignInContext(
                configuration: configuration,
                loginService: OAuthLoginService(),
                usageClient: OpenAICodexUsageClient()
            )
            oauthSuccessMessage = authFlowCoordinator.applyOAuthSignIn(
                state: &state,
                context: context,
                accountNameInput: oauthAccountName,
                fallbackQuota: oauthAccountQuota
            )
            oauthAccountName = ""
            refreshLocalOAuthAccounts()
        } catch {
            oauthError = error.localizedDescription
        }
    }

    private func refreshLocalOAuthAccounts() {
        if loadLocalOAuthAccountsFromBookmark() {
            return
        }

        let discovered = LocalCodexAccountDiscovery.discover()
        localOAuthImportViewModel.applyAutomaticScanResult(discovered)
        normalizeStoredImportedAccountNames()
    }

    private func loadLocalOAuthAccounts(from url: URL) {
        sessionAuthorizedAuthFileURL = url
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let accounts = LocalCodexAccountDiscovery.parseAccounts(from: data, source: url.path)
            localOAuthImportViewModel.applyLoadedAccountsFromFile(accounts)
            normalizeStoredImportedAccountNames()
        } catch {
            localOAuthImportViewModel.applyReadFailure(error)
        }
    }

    private func saveAuthFileBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.codexAuthBookmarkKey)
        } catch {
            localOAuthImportViewModel.applyBookmarkSaveFailure(error)
        }
    }

    @discardableResult
    private func loadLocalOAuthAccountsFromBookmark() -> Bool {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.codexAuthBookmarkKey) else {
            return false
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                saveAuthFileBookmark(for: url)
            }
            sessionAuthorizedAuthFileURL = url
            loadLocalOAuthAccounts(from: url)
            return !localOAuthImportViewModel.accounts.isEmpty
        } catch {
            localOAuthImportViewModel.applyBookmarkInvalid()
            return false
        }
    }

    private func hasSavedAuthFileBookmark() -> Bool {
        UserDefaults.standard.data(forKey: Self.codexAuthBookmarkKey) != nil
    }

    @MainActor
    @discardableResult
    private func openAuthFilePanel() -> Bool {
#if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "選擇"
        panel.message = "請選擇 ~/.codex/auth.json"

        let codexDirectory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex")
        panel.directoryURL = codexDirectory
        panel.nameFieldStringValue = "auth.json"

        if panel.runModal() == .OK, let url = panel.url {
            saveAuthFileBookmark(for: url)
            loadLocalOAuthAccounts(from: url)
            return true
        }
        return false
#else
        localOAuthImportViewModel.errorMessage = "目前平台不支援檔案面板"
        return false
#endif
    }

    @MainActor
    private func importLocalOAuthAccount(_ localAccount: LocalCodexOAuthAccount) async {
        let existingAccessTokens = Set(state.accounts.compactMap(\.apiToken))
        let decision = localOAuthImportViewModel.prepareImport(
            localAccount,
            existingAccessTokens: existingAccessTokens
        )

        guard case .importAccount = decision else {
            return
        }

        do {
            let client = OpenAICodexUsageClient(
                onRawResponse: { raw in
                    Task { @MainActor in
                        lastUsageRawJSON = raw
                    }
                }
            )
            let context = try await authFlowCoordinator.fetchLocalImportContext(
                decision: decision,
                usageClient: client
            )
            authFlowCoordinator.applyLocalImport(state: &state, context: context)

            localOAuthImportViewModel.errorMessage = nil
            syncError = nil
        } catch {
            localOAuthImportViewModel.errorMessage = "無法取得此帳號的即時用量，未匯入：\(authFlowCoordinator.localizedSyncError(error))"
        }
    }

    private func usageSourceLabel(for account: AgentAccount) -> String {
        if account.chatGPTAccountID != nil, account.quota == 100 {
            return "用量來源：response.rate_limit.primary_window.used_percent"
        }
        if account.chatGPTAccountID != nil {
            return "用量來源：response.used_units / quota"
        }
        return "用量來源：手動/本地設定"
    }

    private func isPercentUsageAccount(_ account: AgentAccount) -> Bool {
        account.chatGPTAccountID != nil && account.quota == 100
    }

    private func remainingLabel(for account: AgentAccount) -> String {
        if isPercentUsageAccount(account) {
            return "剩餘 \(account.remainingUnits)%"
        }
        return "剩餘 \(account.remainingUnits)"
    }

    private func usageWindowDetailLabel(for account: AgentAccount) -> String? {
        guard account.chatGPTAccountID != nil else { return nil }

        var segments: [String] = []
        if let usageWindowName = account.usageWindowName, !usageWindowName.isEmpty {
            segments.append("視窗：\(usageWindowName)")
        }
        if let resetAt = account.usageWindowResetAt {
            segments.append(
                "重置：\(resetAt.formatted(.dateTime.month().day().hour().minute()))"
            )
        }
        return segments.isEmpty ? nil : segments.joined(separator: " · ")
    }

    private func usageProgressColor(for account: AgentAccount) -> Color {
        let ratio = account.usageRatio
        if ratio >= 0.9 { return .red }
        if ratio >= 0.7 { return .orange }
        return .blue
    }

    private func normalizeStoredImportedAccountNames() {
        for localAccount in localOAuthImportViewModel.accounts {
            guard let chatGPTAccountID = localAccount.chatGPTAccountID else { continue }
            guard let persisted = state.accounts.first(where: { $0.chatGPTAccountID == chatGPTAccountID }) else { continue }
            guard persisted.name == "Codex OAuth" else { continue }

            let improvedName = localAccount.email ?? localAccount.displayName
            guard !improvedName.isEmpty, improvedName != persisted.name else { continue }
            state.updateAccount(persisted.id, name: improvedName)
        }
    }

    @MainActor
    private func switchAndLaunchCodex(using account: AgentAccount) async {
        lastSwitchLaunchLog = "開始切換：\(account.name)\n"
        guard !account.apiToken.isEmpty else {
            localOAuthImportViewModel.errorMessage = "此帳號沒有可用 token，無法切換"
            appendSwitchLaunchLog("失敗：沒有 token")
            return
        }
        guard let chatGPTAccountID = account.chatGPTAccountID, !chatGPTAccountID.isEmpty else {
            localOAuthImportViewModel.errorMessage = "此帳號缺少 Account ID，無法切換"
            appendSwitchLaunchLog("失敗：沒有 account_id")
            return
        }

        do {
            let authFileURL = try resolveAuthFileURLForSwitch()
            try await performSwitchAndLaunch(
                authFileURL: authFileURL,
                account: account,
                chatGPTAccountID: chatGPTAccountID
            )
            return
        } catch let error as NSError where error.domain == "CodexSwitch" && error.code == 1 {
            appendSwitchLaunchLog("尚未授權 auth.json，啟動選檔流程")
            let didAuthorize = openAuthFilePanel()

            guard didAuthorize else {
                appendSwitchLaunchLog("使用者未完成 auth.json 授權")
                localOAuthImportViewModel.errorMessage = "請先完成 auth.json 授權，才能切換並啟動"
                return
            }

            do {
                appendSwitchLaunchLog("已取得授權，重試切換")
                let authFileURL = try resolveAuthFileURLForSwitch()
                try await performSwitchAndLaunch(
                    authFileURL: authFileURL,
                    account: account,
                    chatGPTAccountID: chatGPTAccountID
                )
                return
            } catch {
                appendSwitchLaunchLog("重試失敗：\(error.localizedDescription)")
                localOAuthImportViewModel.errorMessage = "切換失敗：\(error.localizedDescription)"
                return
            }
        } catch {
            appendSwitchLaunchLog("錯誤：\(error.localizedDescription)")
            localOAuthImportViewModel.errorMessage = "切換失敗：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func performSwitchAndLaunch(
        authFileURL: URL,
        account: AgentAccount,
        chatGPTAccountID: String
    ) async throws {
        let service = CodexAuthSwitchService { line in
            appendSwitchLaunchLog(line)
        }
        try await service.performSwitchAndLaunch(
            authFileURL: authFileURL,
            account: account,
            chatGPTAccountID: chatGPTAccountID
        )
        localOAuthImportViewModel.errorMessage = nil
    }

    private func resolveAuthFileURLForSwitch() throws -> URL {
        if let sessionAuthorizedAuthFileURL {
            return sessionAuthorizedAuthFileURL
        }

        if let bookmark = UserDefaults.standard.data(forKey: Self.codexAuthBookmarkKey) {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                saveAuthFileBookmark(for: url)
            }
            sessionAuthorizedAuthFileURL = url
            return url
        }

        let fallback = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/auth.json")
        if FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }

        throw NSError(
            domain: "CodexSwitch",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "找不到 auth.json，請先按「選擇 auth.json」授權"]
        )
    }

    private func appendSwitchLaunchLog(_ line: String) {
        if lastSwitchLaunchLog.isEmpty {
            lastSwitchLaunchLog = line
        } else {
            lastSwitchLaunchLog += "\n\(line)"
        }
    }
}

#Preview {
    PoolDashboardView(store: UserDefaultsAccountPoolStore(defaults: .standard, key: "preview_account_pool_snapshot"))
}
