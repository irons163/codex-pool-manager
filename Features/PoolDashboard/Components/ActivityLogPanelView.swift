import SwiftUI

struct ActivityLogPanelView: View {
    let activities: [PoolActivity]
    let onClearActivities: () -> Void

    var body: some View {
        GroupBox("近期活動") {
            if activities.isEmpty {
                Text("目前沒有活動紀錄")
                    .foregroundStyle(PoolDashboardTheme.textSecondary)
            } else {
                HStack {
                    Spacer()
                    Button("清除活動紀錄", role: .destructive) {
                        onClearActivities()
                    }
                    .buttonStyle(DashboardWarningButtonStyle())
                }
                List(activities.prefix(8)) { activity in
                    HStack {
                        Text(activity.timestamp.formatted(date: .omitted, time: .standard))
                            .monospacedDigit()
                            .foregroundStyle(PoolDashboardTheme.textMuted)
                            .frame(width: 96, alignment: .leading)
                        Text(activity.message)
                            .foregroundStyle(PoolDashboardTheme.textPrimary)
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(PoolDashboardTheme.panelMutedFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: 1)
                            )
                            .padding(.vertical, PoolDashboardTheme.listRowVerticalInset)
                    )
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 200)
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }
}
