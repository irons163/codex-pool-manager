import SwiftUI

struct ActivityLogPanelView: View {
    let activities: [PoolActivity]
    let onClearActivities: () -> Void

    var body: some View {
        GroupBox("近期活動") {
            if activities.isEmpty {
                Text("目前沒有活動紀錄")
                    .foregroundStyle(.secondary)
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
                        Text(activity.timestamp, format: Date.FormatStyle(date: .omitted, time: .standard))
                            .foregroundStyle(.secondary)
                        Text(activity.message)
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: 160)
            }
        }
    }
}
