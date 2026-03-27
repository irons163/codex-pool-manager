import SwiftUI

struct StrategySettingsPanelView: View {
    let mode: SwitchMode
    let accounts: [AgentAccount]
    let intelligentCandidateName: String?
    let canIntelligentSwitch: Bool
    let intelligentCooldownRemaining: Int

    let modeBinding: Binding<SwitchMode>
    let manualSelectionBinding: Binding<UUID>
    let minSwitchIntervalBinding: Binding<Double>
    let lowThresholdBinding: Binding<Double>
    let minUsageDeltaBinding: Binding<Double>

    var body: some View {
        Picker("切換模式", selection: modeBinding) {
            ForEach(SwitchMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .tint(PoolDashboardTheme.glowA)

        GroupBox("策略設定") {
            VStack(alignment: .leading, spacing: 10) {
                Stepper(
                    "最小切換間隔 \(Int(minSwitchIntervalBinding.wrappedValue)) 秒",
                    value: minSwitchIntervalBinding,
                    in: 30...1800,
                    step: 30
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("低用量提醒門檻 \(Int(lowThresholdBinding.wrappedValue * 100))%")
                    Slider(value: lowThresholdBinding, in: 0.05...0.5, step: 0.01)
                        .tint(PoolDashboardTheme.glowA)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("智能切換最小改善 \(Int(minUsageDeltaBinding.wrappedValue * 100))%")
                    Slider(value: minUsageDeltaBinding, in: 0...0.2, step: 0.01)
                        .tint(PoolDashboardTheme.glowB)
                }

                if mode == .intelligent {
                    if let intelligentCandidateName {
                        Text("推薦切換帳號：\(intelligentCandidateName)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    if canIntelligentSwitch {
                        Text("目前可切換帳號")
                            .font(.subheadline)
                            .foregroundStyle(PoolDashboardTheme.glowB)
                    } else {
                        Text("冷卻中，\(intelligentCooldownRemaining) 秒後可切換")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)

        if mode == .manual, !accounts.isEmpty {
            HStack(spacing: 10) {
                Text("手動帳號")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Picker("手動帳號", selection: manualSelectionBinding) {
                    ForEach(accounts) { account in
                        Text(account.name).tag(account.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }
}
