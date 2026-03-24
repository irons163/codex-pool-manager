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

            if state.mode == .manual {
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
                List(state.accounts) { account in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(account.name)
                            Spacer()
                            Text("\(account.usedUnits)/\(account.quota)")
                                .foregroundStyle(.secondary)
                        }

                        ProgressView(value: account.usageRatio)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
                .frame(minHeight: 200)
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
}

#Preview {
    ContentView()
}
