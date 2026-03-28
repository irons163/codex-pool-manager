import SwiftUI

struct ActiveAccountPanelView: View {
    let activeAccount: AgentAccount?
    let mode: SwitchMode
    let isFocusLockActive: Bool
    let hasLowUsageWarning: Bool
    let lowUsageThresholdRatio: Double
    let showSimulationControl: Bool

    let onSimulateUsage: () -> Void
    let onEvaluateSwitch: () -> Void

    var body: some View {
        GroupBox(L10n.text("active_account.title")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("active_account.subtitle"))
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                if let activeAccount {
                    HStack {
                        Text(activeAccount.name)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(PoolDashboardTheme.textPrimary)
                        Spacer()
                        Text(L10n.text("active_account.remaining_format", activeAccount.remainingUnits))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(PoolDashboardTheme.textSecondary)
                    }
                    .dashboardInfoCard()

                    ProgressView(value: activeAccount.usageRatio)
                        .tint(PoolDashboardTheme.glowB)
                        .scaleEffect(x: 1, y: 1.2, anchor: .center)

                    if isFocusLockActive {
                        PanelStatusCalloutView(
                            message: L10n.text("active_account.focus_lock.message"),
                            title: L10n.text("active_account.focus_lock.title"),
                            tone: .info
                        )
                    }

                    if mode == .focus && hasLowUsageWarning {
                        PanelStatusCalloutView(
                            message: L10n.text("active_account.low_usage.message_format", Int(lowUsageThresholdRatio * 100)),
                            title: L10n.text("active_account.low_usage.title"),
                            tone: .warning
                        )
                    }

                    HStack {
                        if showSimulationControl {
                            Button(L10n.text("active_account.simulate_button")) {
                                onSimulateUsage()
                            }
                            .buttonStyle(DashboardPrimaryButtonStyle())
                        }

                        if showSimulationControl {
                            Button(L10n.text("active_account.run_evaluation")) {
                                onEvaluateSwitch()
                            }
                            .buttonStyle(DashboardSubtleButtonStyle())
                        } else {
                            Button(L10n.text("active_account.run_evaluation")) {
                                onEvaluateSwitch()
                            }
                            .buttonStyle(DashboardPrimaryButtonStyle())
                        }
                    }
                    .dashboardInfoCard()
                } else {
                    Label(L10n.text("active_account.none"), systemImage: "person.crop.circle.badge.exclamationmark")
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sectionCardStyle()
    }
}
