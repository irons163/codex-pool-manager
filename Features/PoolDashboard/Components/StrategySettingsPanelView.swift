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
        Text(L10n.text("strategy.subtitle"))
            .font(.footnote)
            .foregroundStyle(PoolDashboardTheme.textMuted)

        Picker(L10n.text("strategy.switch_mode"), selection: modeBinding) {
            ForEach(visibleModes) { mode in
                Text(localizedModeTitle(mode)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .tint(PoolDashboardTheme.glowA)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PoolDashboardTheme.panelMutedFill)
        )

        GroupBox(L10n.text("strategy.parameters")) {
            VStack(alignment: .leading, spacing: PoolDashboardTheme.strategyPanelSpacing) {
                VStack(alignment: .leading, spacing: PoolDashboardTheme.compactFieldSpacing) {
                    Text(L10n.text("strategy.low_usage_threshold_format", Int(lowThresholdBinding.wrappedValue * 100)))
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                    Slider(value: lowThresholdBinding, in: 0.05...0.5, step: 0.01)
                        .tint(PoolDashboardTheme.glowA)
                }
                .dashboardInfoCard()

                if mode == .intelligent {
                    if let intelligentCandidateName {
                        PanelStatusCalloutView(
                            message: L10n.text("strategy.smart_recommendation.message_format", intelligentCandidateName),
                            title: L10n.text("strategy.smart_recommendation.title"),
                            tone: .info
                        )
                    }

                    if canIntelligentSwitch {
                        PanelStatusCalloutView(
                            message: L10n.text("strategy.switch_allowed.message"),
                            title: L10n.text("strategy.switch_allowed.title"),
                            tone: .success
                        )
                    }
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }

    private func localizedModeTitle(_ mode: SwitchMode) -> String {
        switch mode {
        case .intelligent:
            return L10n.text("mode.intelligent")
        case .manual:
            return L10n.text("mode.manual")
        case .focus:
            return L10n.text("mode.focus")
        }
    }
}
