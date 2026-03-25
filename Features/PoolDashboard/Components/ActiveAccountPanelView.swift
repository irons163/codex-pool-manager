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
            VStack(alignment: .leading, spacing: 8) {
                if let activeAccount {
                    HStack {
                        Text(activeAccount.name)
                            .font(.headline)
                        Spacer()
                        Text("剩餘 \(activeAccount.remainingUnits)")
                            .font(.headline)
                    }

                    ProgressView(value: activeAccount.usageRatio)

                    if isFocusLockActive {
                        Text("專注模式鎖定中")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }

                    if mode == .focus && hasLowUsageWarning {
                        Text("低剩餘用量提醒：目前帳號剩餘不足 \(Int(lowUsageThresholdRatio * 100))%")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }

                    HStack {
                        Button("模擬使用 +50") {
                            onSimulateUsage()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("重新評估切換") {
                            onEvaluateSwitch()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text("目前沒有可用帳號")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
