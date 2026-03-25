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
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.10, blue: 0.18), Color(red: 0.05, green: 0.07, blue: 0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                dashboardHeader
                usageOverviewTiles

            HStack {
                Button(isSyncingUsage ? "同步中..." : "同步 Codex 用量") {
                    Task { await syncCodexUsage() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSyncingUsage)

                if let last = state.lastUsageSyncAt {
                    Text("最近同步：\(last, format: Date.FormatStyle(date: .omitted, time: .standard))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let syncError {
                    Text(syncError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            GroupBox("Debug") {
                VStack(alignment: .leading, spacing: 8) {
                    DisclosureGroup("Last Usage Raw JSON", isExpanded: $showUsageRawJSON) {
                        if lastUsageRawJSON.isEmpty {
                            Text("尚未捕捉到 usage response")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            TextEditor(text: $lastUsageRawJSON)
                                .font(.system(.footnote, design: .monospaced))
                                .frame(minHeight: 120)
                            HStack {
                                Button("清除") {
                                    lastUsageRawJSON = ""
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                            }
                        }
                    }
                    DisclosureGroup("Last Switch Launch Log", isExpanded: $showSwitchLaunchLog) {
                        if lastSwitchLaunchLog.isEmpty {
                            Text("尚未執行切換並啟動")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            TextEditor(text: $lastSwitchLaunchLog)
                                .font(.system(.footnote, design: .monospaced))
                                .frame(minHeight: 120)
                            HStack {
                                Button("清除") {
                                    lastSwitchLaunchLog = ""
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                            }
                        }
                    }
                }
            }

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

            GroupBox("備份與還原") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button("匯出 JSON") {
                            do {
                                backupJSON = try AccountPoolSnapshotCodec.exportJSON(state.snapshot)
                                backupError = nil
                            } catch {
                                backupError = "匯出失敗：\(error.localizedDescription)"
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("匯出（可重抓）") {
                            do {
                                backupJSON = try AccountPoolSnapshotCodec.exportJSON(state.snapshot, redactSensitive: false)
                                backupError = nil
                            } catch {
                                backupError = "匯出失敗：\(error.localizedDescription)"
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("匯入 JSON") {
                            do {
                                let snapshot = try AccountPoolSnapshotCodec.importJSON(backupJSON)
                                state = AccountPoolState(snapshot: snapshot)
                                backupError = nil
                                Task { await syncCodexUsage() }
                            } catch {
                                backupError = "匯入失敗：\(error.localizedDescription)"
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Text("警告：匯出（可重抓）會包含 access token 與 account id，僅限你自己保管，勿分享。")
                        .font(.footnote)
                        .foregroundStyle(.orange)

                    TextEditor(text: $backupJSON)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 140)

                    if let backupError {
                        Text(backupError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .frame(maxWidth: 1160, alignment: .leading)
            .padding(20)
        }
        }
        .frame(minWidth: 900, minHeight: 620)
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

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Codex Account Orchestrator")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("管理 OAuth 帳號、監控用量、快速切換執行環境")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.bottom, 4)
    }

    private var usageOverviewTiles: some View {
        HStack(spacing: 12) {
            overviewTile(title: "帳號", value: "\(state.accounts.count)", tone: .blue)
            overviewTile(title: "可用", value: "\(state.availableAccountsCount)", tone: .green)
            overviewTile(title: "總用量", value: "\(Int(state.overallUsageRatio * 100))%", tone: .orange)
            overviewTile(
                title: "模式",
                value: state.mode.rawValue,
                tone: state.mode == .focus ? .purple : .indigo
            )
        }
    }

    private func overviewTile(title: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(tone.opacity(0.35), lineWidth: 1)
                )
        )
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
            let client = OpenAICodexUsageClient(
                onRawResponse: { raw in
                    Task { @MainActor in
                        lastUsageRawJSON = raw
                    }
                }
            )
            let service = CodexUsageSyncService(client: client)
            var nextState = state
            try await service.sync(state: &nextState)
            state = nextState
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

        guard let issuerURL = URL(string: oauthIssuer.trimmingCharacters(in: .whitespacesAndNewlines)),
              !oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !oauthScopes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !oauthRedirectURI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            oauthError = "請至少填入 Client ID（其餘欄位有預設值）"
            return
        }

        let configuration = OAuthClientConfiguration(
            issuer: issuerURL,
            clientID: oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines),
            scopes: oauthScopes.trimmingCharacters(in: .whitespacesAndNewlines),
            redirectURI: oauthRedirectURI.trimmingCharacters(in: .whitespacesAndNewlines),
            originator: oauthOriginator.trimmingCharacters(in: .whitespacesAndNewlines),
            forcedWorkspaceID: oauthWorkspaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : oauthWorkspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        do {
            let tokens = try await OAuthLoginService().signIn(configuration: configuration)
            let claims = OAuthIDTokenClaimsParser.parse(tokens.idToken)

            var resolvedAccountID = claims?.accountID ?? claims?.subject
            var resolvedEmail = claims?.email
            var resolvedQuota = oauthAccountQuota
            var resolvedUsedUnits = 0
            var resolvedWindowName: String?
            var resolvedWindowResetAt: Date?

            if let accountID = resolvedAccountID, !accountID.isEmpty {
                do {
                    let usage = try await OpenAICodexUsageClient().fetchUsage(
                        accessToken: tokens.accessToken,
                        accountID: accountID
                    )
                    resolvedAccountID = usage.accountID ?? resolvedAccountID
                    resolvedEmail = usage.accountEmail ?? resolvedEmail
                    resolvedQuota = usage.quota
                    resolvedUsedUnits = usage.usedUnits
                    resolvedWindowName = usage.usageWindowName
                    resolvedWindowResetAt = usage.usageWindowResetAt
                } catch {
                    // Keep account creation flow robust; user can sync again later.
                }
            }

            let accountNameInput = oauthAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedAccountName = accountNameInput.isEmpty
                ? (resolvedEmail ?? "OAuth Account")
                : accountNameInput

            let existingAccountID = OAuthAccountUpsertResolver.resolveExistingAccountID(
                in: state.accounts,
                chatGPTAccountID: resolvedAccountID,
                accessToken: tokens.accessToken,
                email: resolvedEmail
            )

            if let existingAccountID {
                let existingAccount = state.accounts.first(where: { $0.id == existingAccountID })
                let shouldReplacePlaceholderName = accountNameInput.isEmpty
                    && (existingAccount?.name == "OAuth Account" || existingAccount?.name.isEmpty == true)
                let updatedName = accountNameInput.isEmpty
                    ? (shouldReplacePlaceholderName ? resolvedAccountName : (existingAccount?.name ?? resolvedAccountName))
                    : resolvedAccountName

                state.updateAccount(
                    existingAccountID,
                    name: updatedName,
                    quota: resolvedQuota,
                    usedUnits: resolvedUsedUnits,
                    apiToken: tokens.accessToken,
                    chatGPTAccountID: resolvedAccountID,
                    usageWindowName: resolvedWindowName,
                    usageWindowResetAt: resolvedWindowResetAt,
                    now: .now
                )
                oauthSuccessMessage = "登入成功，已更新既有帳號"
            } else {
                let newAccountID = state.addAccount(
                    name: resolvedAccountName,
                    quota: resolvedQuota,
                    usedUnits: resolvedUsedUnits,
                    chatGPTAccountID: resolvedAccountID,
                    usageWindowName: resolvedWindowName,
                    usageWindowResetAt: resolvedWindowResetAt
                )
                state.updateAccount(
                    newAccountID,
                    apiToken: tokens.accessToken,
                    chatGPTAccountID: resolvedAccountID,
                    now: .now
                )
                oauthSuccessMessage = "登入成功，已新增帳號"
            }
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

        guard case let .importAccount(name, accessToken, chatGPTAccountID) = decision else {
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
            let usage = try await client.fetchUsage(
                accessToken: accessToken,
                accountID: chatGPTAccountID
            )
            let normalizedEmail = usage.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = (normalizedEmail?.isEmpty == false) ? (normalizedEmail ?? name) : name
            let resolvedAccountID = usage.accountID ?? chatGPTAccountID

            let existingAccountID = OAuthAccountUpsertResolver.resolveExistingAccountID(
                in: state.accounts,
                chatGPTAccountID: resolvedAccountID,
                accessToken: accessToken,
                email: normalizedEmail
            )

            if let existingAccountID {
                state.updateAccount(
                    existingAccountID,
                    name: resolvedName,
                    quota: usage.quota,
                    usedUnits: usage.usedUnits,
                    apiToken: accessToken,
                    chatGPTAccountID: resolvedAccountID,
                    usageWindowName: usage.usageWindowName,
                    usageWindowResetAt: usage.usageWindowResetAt
                )
            } else {
                let newAccountID = state.addAccount(
                    name: resolvedName,
                    quota: usage.quota,
                    usedUnits: usage.usedUnits,
                    chatGPTAccountID: resolvedAccountID,
                    usageWindowName: usage.usageWindowName,
                    usageWindowResetAt: usage.usageWindowResetAt
                )
                state.updateAccount(
                    newAccountID,
                    apiToken: accessToken,
                    chatGPTAccountID: resolvedAccountID,
                    usageWindowName: usage.usageWindowName,
                    usageWindowResetAt: usage.usageWindowResetAt
                )
            }

            localOAuthImportViewModel.errorMessage = nil
            syncError = nil
        } catch {
            localOAuthImportViewModel.errorMessage = "無法取得此帳號的即時用量，未匯入：\(localizedCodexSyncError(error))"
        }
    }

    private func localizedCodexSyncError(_ error: Error) -> String {
        if let syncError = error as? CodexSyncError {
            return syncError.localizedDescription
        }

        if let http = error as? CodexClientHTTPError {
            if http.statusCode == 401 || http.statusCode == 403 {
                return CodexSyncError.unauthorized.localizedDescription
            }
            if http.statusCode == 429 {
                return CodexSyncError.rateLimited.localizedDescription
            }
            return CodexSyncError.unknown.localizedDescription
        }

        if error is URLError {
            return CodexSyncError.network.localizedDescription
        }

        return CodexSyncError.unknown.localizedDescription
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
            try await performSwitchAndLaunch(
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
                try await performSwitchAndLaunch(
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
    private func performSwitchAndLaunch(account: AgentAccount, chatGPTAccountID: String) async throws {
        do {
            let authFileURL = try resolveAuthFileURLForSwitch()
            appendSwitchLaunchLog("使用 auth.json：\(authFileURL.path)")
            let hasSecurityScope = authFileURL.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    authFileURL.stopAccessingSecurityScopedResource()
                }
            }

            let originalData = try Data(contentsOf: authFileURL)
            let rewrittenData = try CodexAuthFileSwitcher.rewriteAuthJSON(
                originalData,
                accessToken: account.apiToken,
                accountID: chatGPTAccountID,
                email: account.name.contains("@") ? account.name : nil
            )
            try rewrittenData.write(to: authFileURL, options: .atomic)
            appendSwitchLaunchLog("auth.json 已改寫")

            try await relaunchCodexApp()
            appendSwitchLaunchLog("啟動完成")
            localOAuthImportViewModel.errorMessage = nil
        } catch {
            throw error
        }
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

    private func relaunchCodexApp() async throws {
#if canImport(AppKit)
        let workspace = NSWorkspace.shared

        let running = workspace.runningApplications
        appendSwitchLaunchLog("目前執行中 app 數量：\(running.count)")

        let knownBundleIDs = ["com.openai.chatgpt", "com.openai.codex"]
        for bundleIdentifier in knownBundleIDs {
            let closed = await closeAppIfRunning(bundleIdentifier: bundleIdentifier)
            if !closed {
                throw NSError(
                    domain: "CodexSwitch",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "偵測到 \(bundleIdentifier) 仍在執行。Sandbox 模式無法自動關閉其他 App，請先手動關閉後再試。"]
                )
            }
        }

        if try await launchCodexAppWithRetry() {
            return
        }

        throw NSError(
            domain: "CodexSwitch",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "已切換 auth.json，但找不到可啟動的 Codex/ChatGPT App"]
        )
#else
        throw NSError(
            domain: "CodexSwitch",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "目前平台不支援啟動 Codex App"]
        )
#endif
    }

    private func closeAppIfRunning(bundleIdentifier: String) async -> Bool {
#if canImport(AppKit)
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard !runningApps.isEmpty else {
            appendSwitchLaunchLog("未偵測到執行中：\(bundleIdentifier)")
            return true
        }

        appendSwitchLaunchLog("偵測到執行中：\(bundleIdentifier)（\(runningApps.count)）")

        if isSandboxedEnvironment {
            appendSwitchLaunchLog("Sandbox 模式下無法自動關閉其他 App，請手動關閉後再切換")
            return false
        }

        for runningApp in runningApps {
            let pid = runningApp.processIdentifier
            let didTerminate = runningApp.terminate()
            appendSwitchLaunchLog("嘗試關閉 pid=\(pid) -> \(didTerminate ? "terminate" : "terminate failed")")
            if !didTerminate {
                let didForceTerminate = runningApp.forceTerminate()
                appendSwitchLaunchLog("嘗試強制關閉 pid=\(pid) -> \(didForceTerminate ? "forceTerminate" : "forceTerminate failed")")
            }
        }

        let didExit = await waitUntilAppExits(bundleIdentifier: bundleIdentifier, timeoutNanoseconds: 8_000_000_000)
        if didExit {
            appendSwitchLaunchLog("已關閉：\(bundleIdentifier)")
            return true
        }

        appendSwitchLaunchLog("仍在執行：\(bundleIdentifier)（可能受權限限制）")
        return false
#else
        return true
#endif
    }

    private func launchCodexAppWithRetry(maxAttempts: Int = 6) async throws -> Bool {
        for attempt in 1...maxAttempts {
            appendSwitchLaunchLog("啟動嘗試 #\(attempt)")
            if try await launchApp(bundleIdentifier: "com.openai.chatgpt") {
                appendSwitchLaunchLog("啟動成功：com.openai.chatgpt")
                return true
            }
            if try await launchApp(bundleIdentifier: "com.openai.codex") {
                appendSwitchLaunchLog("啟動成功：com.openai.codex")
                return true
            }
            if try await launchApp(at: URL(fileURLWithPath: "/Applications/ChatGPT.app")) {
                appendSwitchLaunchLog("啟動成功：/Applications/ChatGPT.app")
                return true
            }
            if try await launchApp(at: URL(fileURLWithPath: "/Applications/Codex.app")) {
                appendSwitchLaunchLog("啟動成功：/Applications/Codex.app")
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        appendSwitchLaunchLog("多次嘗試後仍無法啟動 Codex/ChatGPT")
        return false
    }

    private func waitUntilAppExits(bundleIdentifier: String, timeoutNanoseconds: UInt64) async -> Bool {
#if canImport(AppKit)
        let interval: UInt64 = 200_000_000
        var waited: UInt64 = 0
        while waited < timeoutNanoseconds {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
                return true
            }
            try? await Task.sleep(nanoseconds: interval)
            waited += interval
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
#else
        return true
#endif
    }

    private func launchApp(bundleIdentifier: String) async throws -> Bool {
#if canImport(AppKit)
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            appendSwitchLaunchLog("找不到 bundle id：\(bundleIdentifier)")
            return false
        }
        appendSwitchLaunchLog("找到 bundle id \(bundleIdentifier) -> \(url.path)")
        return try await launchApp(at: url)
#else
        return false
#endif
    }

    private func launchApp(at url: URL) async throws -> Bool {
#if canImport(AppKit)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: true)
                }
            }
        }
#else
        return false
#endif
    }

    private var isSandboxedEnvironment: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
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
