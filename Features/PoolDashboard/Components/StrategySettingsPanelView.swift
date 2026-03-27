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
        Text("Control how the runtime selects and rotates accounts.")
            .font(.footnote)
            .foregroundStyle(PoolDashboardTheme.textMuted)

        Picker("Switch Mode", selection: modeBinding) {
            ForEach(SwitchMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .tint(PoolDashboardTheme.glowA)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PoolDashboardTheme.panelMutedFill)
        )

        GroupBox("Strategy Parameters") {
            VStack(alignment: .leading, spacing: PoolDashboardTheme.strategyPanelSpacing) {
                Stepper(
                    "Minimum switch interval: \(Int(minSwitchIntervalBinding.wrappedValue))s",
                    value: minSwitchIntervalBinding,
                    in: 30...1800,
                    step: 30
                )

                VStack(alignment: .leading, spacing: PoolDashboardTheme.compactFieldSpacing) {
                    Text("Low-usage alert threshold: \(Int(lowThresholdBinding.wrappedValue * 100))%")
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                    Slider(value: lowThresholdBinding, in: 0.05...0.5, step: 0.01)
                        .tint(PoolDashboardTheme.glowA)
                }

                VStack(alignment: .leading, spacing: PoolDashboardTheme.compactFieldSpacing) {
                    Text("Minimum improvement for smart switch: \(Int(minUsageDeltaBinding.wrappedValue * 100))%")
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                    Slider(value: minUsageDeltaBinding, in: 0...0.2, step: 0.01)
                        .tint(PoolDashboardTheme.glowB)
                }

                if mode == .intelligent {
                    if let intelligentCandidateName {
                        Text("Recommended next account: \(intelligentCandidateName)")
                            .font(.subheadline)
                            .foregroundStyle(PoolDashboardTheme.textSecondary)
                    }

                    if canIntelligentSwitch {
                        Text("Smart switch is currently allowed")
                            .font(.subheadline)
                            .foregroundStyle(PoolDashboardTheme.glowB)
                    } else {
                        Text("Cooldown active: available in \(intelligentCooldownRemaining)s")
                            .font(.subheadline)
                            .foregroundStyle(PoolDashboardTheme.textSecondary)
                    }
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)

        if mode == .manual, !accounts.isEmpty {
            HStack(spacing: 10) {
                Text("Manual account")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textSecondary)
                Picker("Manual account", selection: manualSelectionBinding) {
                    ForEach(accounts) { account in
                        Text(account.name).tag(account.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: PoolDashboardTheme.controlCornerRadius, style: .continuous)
                    .fill(PoolDashboardTheme.panelMutedFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.controlCornerRadius, style: .continuous)
                            .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: 1)
                    )
            )
        }
    }
}
