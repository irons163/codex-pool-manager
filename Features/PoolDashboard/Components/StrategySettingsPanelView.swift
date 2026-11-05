import SwiftUI

struct StrategySettingsPanelView: View {
    let mode: SwitchMode
    let accounts: [AgentAccount]
    var orderedAccounts: [AgentAccount] = []
    let activeAccount: AgentAccount?
    let intelligentCandidateName: String?
    let canIntelligentSwitch: Bool
    let intelligentCooldownRemaining: Int
    let hasLowUsageWarning: Bool
    var moveOrderedAccount: ((UUID, Int) -> Void)? = nil

    let modeBinding: Binding<SwitchMode>
    let manualSelectionBinding: Binding<UUID>
    let minSwitchIntervalBinding: Binding<Double>
    let switchThresholdBinding: Binding<Double>
    let lowUsageAlertThresholdBinding: Binding<Double>
    let lowUsageAlertsEnabledBinding: Binding<Bool>
    private var visibleModes: [SwitchMode] {
        [.intelligent, .ordered, .focus]
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
                    Toggle(L10n.text("strategy.low_usage_alert_enabled"), isOn: lowUsageAlertsEnabledBinding)
                        .toggleStyle(.switch)

                    Text(
                        L10n.text(
                            "strategy.low_usage_alert_threshold_format",
                            Int(lowUsageAlertThresholdBinding.wrappedValue * 100)
                        )
                    )
                    .foregroundStyle(PoolDashboardTheme.textSecondary)
                    Slider(value: lowUsageAlertThresholdBinding, in: 0.05...0.5, step: 0.01)
                        .tint(PoolDashboardTheme.glowA)
                        .disabled(!lowUsageAlertsEnabledBinding.wrappedValue)
                }
                .dashboardInfoCard()
                .opacity(lowUsageAlertsEnabledBinding.wrappedValue ? 1 : 0.65)

                if mode == .intelligent || mode == .ordered {
                    VStack(alignment: .leading, spacing: PoolDashboardTheme.compactFieldSpacing) {
                        Text(
                            mode == .ordered
                                ? L10n.text("strategy.order.threshold_format", Int(switchThresholdBinding.wrappedValue * 100))
                                : L10n.text("strategy.low_usage_threshold_format", Int(switchThresholdBinding.wrappedValue * 100))
                        )
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                        Slider(value: switchThresholdBinding, in: 0...0.5, step: 0.01)
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

        if mode == .ordered {
            orderedAccountsSection
        }
    }

    private var orderedAccountsSection: some View {
        GroupBox(L10n.text("strategy.order.title")) {
            VStack(alignment: .leading, spacing: PoolDashboardTheme.strategyPanelSpacing) {
                Text(L10n.text("strategy.order.hint"))
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                if orderedAccounts.isEmpty {
                    Text(L10n.text("strategy.order.empty"))
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                        .dashboardInfoCard()
                } else {
                    ForEach(Array(orderedAccounts.enumerated()), id: \.element.id) { index, account in
                        orderedAccountRow(index: index, account: account)
                    }
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }

    private func orderedAccountRow(index: Int, account: AgentAccount) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1).")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(PoolDashboardTheme.textMuted)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .foregroundStyle(PoolDashboardTheme.textPrimary)
                if account.isUsageSyncExcluded {
                    Text(L10n.text("strategy.order.excluded"))
                        .font(.caption)
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                }
            }

            Spacer(minLength: 8)

            Button {
                moveOrderedAccount?(account.id, -1)
            } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            .help(L10n.text("strategy.order.move_up"))

            Button {
                moveOrderedAccount?(account.id, 1)
            } label: {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(.plain)
            .disabled(index == orderedAccounts.count - 1)
            .help(L10n.text("strategy.order.move_down"))
        }
        .dashboardInfoCard()
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
        case .ordered:
            return L10n.text("mode.ordered")
        case .manual:
            return L10n.text("mode.manual")
        case .focus:
            return L10n.text("mode.focus")
        }
    }
}
