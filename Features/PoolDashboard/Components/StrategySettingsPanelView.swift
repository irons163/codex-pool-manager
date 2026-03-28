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

    private var visibleModes: [SwitchMode] {
        [.intelligent, .focus]
    }

    var body: some View {
        Text("Control how runtime selects and rotates accounts.")
            .font(.footnote)
            .foregroundStyle(PoolDashboardTheme.textMuted)

        Picker("Switch Mode", selection: modeBinding) {
            ForEach(visibleModes) { mode in
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
                VStack(alignment: .leading, spacing: PoolDashboardTheme.compactFieldSpacing) {
                    Text("Low-usage alert threshold: \(Int(lowThresholdBinding.wrappedValue * 100))%")
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                    Slider(value: lowThresholdBinding, in: 0.05...0.5, step: 0.01)
                        .tint(PoolDashboardTheme.glowA)
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
                    }
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }
}
