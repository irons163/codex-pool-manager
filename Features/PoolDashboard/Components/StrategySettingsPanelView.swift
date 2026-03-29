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
    let switchWithoutLaunchingBinding: Binding<Bool>
    let autoSyncEnabledBinding: Binding<Bool>
    let autoSyncIntervalSecondsBinding: Binding<Double>
    let languageOverrideBinding: Binding<String>
    let languageOptions: [L10n.LanguageOption]

    private var visibleModes: [SwitchMode] {
        [.intelligent, .focus]
    }

    private var switchAndLaunchBinding: Binding<Bool> {
        Binding(
            get: { !switchWithoutLaunchingBinding.wrappedValue },
            set: { switchWithoutLaunchingBinding.wrappedValue = !$0 }
        )
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
                    VStack(alignment: .leading, spacing: PoolDashboardTheme.compactFieldSpacing) {
                        Text(
                            L10n.text(
                                "strategy.switch_threshold_format",
                                Int(minUsageDeltaBinding.wrappedValue * 100)
                            )
                        )
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                        Slider(value: minUsageDeltaBinding, in: 0...0.5, step: 0.01)
                            .tint(PoolDashboardTheme.glowA)
                    }
                    .dashboardInfoCard()

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

        GroupBox(L10n.text("strategy.general_settings")) {
            VStack(alignment: .leading, spacing: PoolDashboardTheme.strategyPanelSpacing) {
                Toggle(L10n.text("strategy.switch_without_launch"), isOn: switchAndLaunchBinding)
                    .toggleStyle(.switch)
                    .tint(PoolDashboardTheme.glowA)
                    .foregroundStyle(PoolDashboardTheme.textSecondary)
                    .dashboardInfoCard()

                VStack(alignment: .leading, spacing: PoolDashboardTheme.compactFieldSpacing) {
                    Toggle(L10n.text("strategy.auto_sync_enabled"), isOn: autoSyncEnabledBinding)
                        .toggleStyle(.switch)
                        .tint(PoolDashboardTheme.glowA)
                        .foregroundStyle(PoolDashboardTheme.textSecondary)

                    Text(
                        L10n.text(
                            "strategy.auto_sync_interval_seconds_format",
                            Int(autoSyncIntervalSecondsBinding.wrappedValue)
                        )
                    )
                    .foregroundStyle(PoolDashboardTheme.textSecondary)

                    Slider(value: autoSyncIntervalSecondsBinding, in: 5...300, step: 1)
                        .tint(PoolDashboardTheme.glowA)
                        .disabled(!autoSyncEnabledBinding.wrappedValue)
                }
                .dashboardInfoCard()

                VStack(alignment: .leading, spacing: PoolDashboardTheme.compactFieldSpacing) {
                    Text(L10n.text("strategy.language"))
                        .foregroundStyle(PoolDashboardTheme.textSecondary)

                    Picker(L10n.text("strategy.language"), selection: languageOverrideBinding) {
                        ForEach(languageOptions) { option in
                            Text(option.title).tag(option.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(PoolDashboardTheme.glowA)
                }
                .dashboardInfoCard()
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
