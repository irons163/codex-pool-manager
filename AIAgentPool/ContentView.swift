import SwiftUI

struct ContentView: View {
    @State private var state: AccountPoolState
    @State private var newAccountName = ""
    @State private var newAccountQuota = 1000
    @State private var showLowUsageAlert = false
    @State private var lowUsageAlertPolicy = LowUsageAlertPolicy()
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Codex 帳號池")
                .font(.largeTitle)
                .fontWeight(.semibold)

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
                    Button("重設全部用量") {
                        state.resetAllUsage()
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
                                    TextField("帳號名稱", text: accountNameBinding(accountID: account.id))
                                        .textFieldStyle(.roundedBorder)
                                    Spacer()
                                    Button("重設用量") {
                                        state.resetUsage(for: account.id)
                                    }
                                    .buttonStyle(.bordered)
                                    Button("刪除", role: .destructive) {
                                        state.removeAccount(account.id)
                                    }
                                }

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

                                ProgressView(value: account.usageRatio)
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
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 520)
        .onAppear {
            state.evaluate()
            _ = lowUsageAlertPolicy.shouldTriggerAlert(mode: state.mode, hasLowUsageWarning: state.hasLowUsageWarning)
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
}

#Preview {
    ContentView(store: UserDefaultsAccountPoolStore(defaults: .standard, key: "preview_account_pool_snapshot"))
}
