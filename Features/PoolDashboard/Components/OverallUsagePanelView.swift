import SwiftUI

struct OverallUsagePanelView: View {
    let totalUsedUnits: Int
    let totalQuota: Int
    let overallUsageRatio: Double
    let availableAccountsCount: Int
    let isPoolExhausted: Bool
    let resetAllButtonTitle: String
    let onResetAll: () -> Void

    var body: some View {
        GroupBox("整體用量") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("總用量 \(totalUsedUnits)/\(totalQuota)")
                    Spacer()
                    Text("\(Int(overallUsageRatio * 100))%")
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: overallUsageRatio)

                Button(resetAllButtonTitle) {
                    onResetAll()
                }
                .buttonStyle(.bordered)

                HStack {
                    Text("可用帳號數 \(availableAccountsCount)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                if isPoolExhausted {
                    Text("所有帳號用量已耗盡，請補充配額或重設用量。")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
