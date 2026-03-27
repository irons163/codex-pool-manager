import SwiftUI

struct ActiveAccountPanelView: View {
    let activeAccount: AgentAccount?
    let mode: SwitchMode
    let isFocusLockActive: Bool
    let hasLowUsageWarning: Bool
    let lowUsageThresholdRatio: Double

    let onSimulateUsage: () -> Void
    let onEvaluateSwitch: () -> Void

    var body: some View {
        GroupBox("Active Account") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Inspect live consumption and trigger switch evaluation immediately.")
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                if let activeAccount {
                    HStack {
                        Text(activeAccount.name)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(PoolDashboardTheme.textPrimary)
                        Spacer()
                        Text("Remaining \(activeAccount.remainingUnits)")
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
                            message: "Runtime is currently pinned to the active account for deterministic execution.",
                            title: "Focus Lock Active",
                            tone: .info
                        )
                    }

                    if mode == .focus && hasLowUsageWarning {
                        PanelStatusCalloutView(
                            message: "Remaining balance is below \(Int(lowUsageThresholdRatio * 100))%. Consider switching soon.",
                            title: "Low Usage Warning",
                            tone: .warning
                        )
                    }

                    HStack {
                        Button("Simulate +50") {
                            onSimulateUsage()
                        }
                        .buttonStyle(DashboardPrimaryButtonStyle())

                        Button("Re-evaluate switch") {
                            onEvaluateSwitch()
                        }
                        .buttonStyle(DashboardSubtleButtonStyle())
                    }
                } else {
                    Label("No available account", systemImage: "person.crop.circle.badge.exclamationmark")
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sectionCardStyle()
    }
}
