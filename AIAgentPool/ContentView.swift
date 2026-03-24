import SwiftUI

struct ContentView: View {
    @State private var state = AccountPoolState(
        accounts: [
            AgentAccount(id: UUID(), name: "Codex-Team-A", usedUnits: 120, quota: 1000),
            AgentAccount(id: UUID(), name: "Codex-Team-B", usedUnits: 460, quota: 1000),
            AgentAccount(id: UUID(), name: "Codex-Team-C", usedUnits: 780, quota: 1000)
        ],
        mode: .intelligent,
        minSwitchInterval: 300,
        lowUsageThresholdRatio: 0.15
    )
    @State private var newAccountName = ""
    @State private var newAccountQuota = 1000

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

                        if state.mode == .focus && state.hasLowUsageWarning {
                            Text("低剩餘用量提醒：目前帳號剩餘不足 15%")
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
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 520)
        .onAppear {
            state.evaluate()
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
    ContentView()
}
