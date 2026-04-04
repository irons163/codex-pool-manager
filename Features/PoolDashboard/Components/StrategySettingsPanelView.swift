import SwiftUI

struct StrategySettingsPanelView: View {
    let mode: SwitchMode
    let accounts: [AgentAccount]
    let activeAccount: AgentAccount?
    let intelligentCandidateName: String?
    let canIntelligentSwitch: Bool
    let intelligentCooldownRemaining: Int
    let hasLowUsageWarning: Bool

    let modeBinding: Binding<SwitchMode>
    let manualSelectionBinding: Binding<UUID>
    let minSwitchIntervalBinding: Binding<Double>
    let switchThresholdBinding: Binding<Double>
    let lowUsageAlertThresholdBinding: Binding<Double>
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
                    Text(
                        L10n.text(
                            "strategy.low_usage_alert_threshold_format",
                            Int(lowUsageAlertThresholdBinding.wrappedValue * 100)
                        )
                    )
                    .foregroundStyle(PoolDashboardTheme.textSecondary)
                    Slider(value: lowUsageAlertThresholdBinding, in: 0.05...0.5, step: 0.01)
                        .tint(PoolDashboardTheme.glowA)
                }
                .dashboardInfoCard()

                if mode == .intelligent {
                    VStack(alignment: .leading, spacing: PoolDashboardTheme.compactFieldSpacing) {
                        Text(L10n.text("strategy.low_usage_threshold_format", Int(switchThresholdBinding.wrappedValue * 100)))
                            .foregroundStyle(PoolDashboardTheme.textSecondary)
                        Slider(value: switchThresholdBinding, in: 0.05...0.5, step: 0.01)
                            .tint(PoolDashboardTheme.glowA)
                    }
                    .dashboardInfoCard()
                }

                if hasLowUsageWarning {
                    lowUsageStatusCallout
                }

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

    @ViewBuilder
    private var lowUsageStatusCallout: some View {
        if let activeAccount {
            let thresholdPercent = Int((lowUsageAlertThresholdBinding.wrappedValue * 100).rounded())
            let remainingPercent = intelligentRemainingPercent(for: activeAccount)

            PanelStatusCalloutView(
                message: L10n.text("strategy.low_usage_state_low_format", remainingPercent, thresholdPercent),
                title: L10n.text("active_account.low_usage.title"),
                tone: .warning
            )
        } else {
            PanelStatusCalloutView(
                message: L10n.text("active_account.none"),
                title: L10n.text("active_account.low_usage.title"),
                tone: .info
            )
        }
    }

    private func intelligentRemainingPercent(for account: AgentAccount) -> Int {
        account.smartSwitchRemainingPercent
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
