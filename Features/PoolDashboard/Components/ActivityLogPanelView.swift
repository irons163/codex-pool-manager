import SwiftUI

struct ActivityLogPanelView: View {
    let activities: [PoolActivity]
    let onClearActivities: () -> Void

    var body: some View {
        GroupBox("近期活動") {
            if activities.isEmpty {
                Text("目前沒有活動紀錄")
                    .foregroundStyle(.white.opacity(0.72))
            } else {
                HStack {
                    Spacer()
                    Button("清除活動紀錄", role: .destructive) {
                        onClearActivities()
                    }
                    .buttonStyle(.bordered)
                }
                List(activities.prefix(8)) { activity in
                    HStack {
                        Text(activity.timestamp.formatted(date: .omitted, time: .standard))
                            .foregroundStyle(.white.opacity(0.62))
                        Text(activity.message)
                            .foregroundStyle(.white.opacity(0.90))
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(PoolDashboardTheme.panelFill.opacity(0.60))
                            .padding(.vertical, 2)
                    )
                }
                .listStyle(.plain)
                .frame(minHeight: 160)
            }
        }
        .tint(PoolDashboardTheme.glowA)
    }
}
