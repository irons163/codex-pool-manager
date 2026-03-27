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
        Text("Control how runtime selects and rotates accounts.")
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
                .dashboardInfoCard()

                VStack(alignment: .leading, spacing: PoolDashboardTheme.compactFieldSpacing) {
                    Text("Low-usage alert threshold: \(Int(lowThresholdBinding.wrappedValue * 100))%")
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                    Slider(value: lowThresholdBinding, in: 0.05...0.5, step: 0.01)
                        .tint(PoolDashboardTheme.glowA)
                }
                .dashboardInfoCard()

                VStack(alignment: .leading, spacing: PoolDashboardTheme.compactFieldSpacing) {
                    Text("Minimum improvement for smart switch: \(Int(minUsageDeltaBinding.wrappedValue * 100))%")
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                    Slider(value: minUsageDeltaBinding, in: 0...0.2, step: 0.01)
                        .tint(PoolDashboardTheme.glowB)
                }
                .dashboardInfoCard()

                if mode == .intelligent {
                    if let intelligentCandidateName {
                        PanelStatusCalloutView(
                            message: "Recommended next account is \(intelligentCandidateName).",
                            title: "Smart Recommendation",
                            tone: .info
                        )
                    }

                    if canIntelligentSwitch {
                        PanelStatusCalloutView(
                            message: "Smart switch conditions are satisfied.",
                            title: "Switch Allowed",
                            tone: .success
                        )
                    } else {
                        PanelStatusCalloutView(
                            message: "Cooldown active. Available in \(intelligentCooldownRemaining)s.",
                            title: "Switch Delayed",
                            tone: .warning
                        )
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
