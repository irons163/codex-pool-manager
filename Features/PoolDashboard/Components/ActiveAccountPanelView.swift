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
        GroupBox("目前使用帳號") {
            VStack(alignment: .leading, spacing: 10) {
                if let activeAccount {
                    HStack {
                        Text(activeAccount.name)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Spacer()
                        Text("剩餘 \(activeAccount.remainingUnits)")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }

                    ProgressView(value: activeAccount.usageRatio)
                        .tint(PoolDashboardTheme.glowB)

                    if isFocusLockActive {
                        Text("專注模式鎖定中")
                            .font(.subheadline)
                            .foregroundStyle(PoolDashboardTheme.glowA)
                    }

                    if mode == .focus && hasLowUsageWarning {
                        Text("低剩餘用量提醒：目前帳號剩餘不足 \(Int(lowUsageThresholdRatio * 100))%")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.orange.opacity(0.18))
                            )
                    }

                    HStack {
                        Button("模擬使用 +50") {
                            onSimulateUsage()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PoolDashboardTheme.glowA)

                        Button("重新評估切換") {
                            onEvaluateSwitch()
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                } else {
                    Label("目前沒有可用帳號", systemImage: "person.crop.circle.badge.exclamationmark")
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sectionCardStyle()
    }
}
