import SwiftUI

struct ActivityLogPanelView: View {
    let activities: [PoolActivity]
    let onClearActivities: () -> Void

    var body: some View {
        GroupBox(L10n.text("activity_feed.title")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.text("activity_feed.subtitle"))
                        .font(.footnote)
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                    Spacer()
                    Text("\(activities.count)")
                        .statusBadge(tone: PoolDashboardTheme.panelMutedFill)
                }

                if activities.isEmpty {
                    PanelStatusCalloutView(
                        message: L10n.text("activity_feed.empty.message"),
                        title: L10n.text("activity_feed.empty.title"),
                        tone: .info
                    )
                } else {
                    HStack {
                        Spacer()
                        Button(L10n.text("activity_feed.clear"), role: .destructive) {
                            onClearActivities()
                        }
                        .buttonStyle(DashboardWarningButtonStyle())
                    }

                    List(activities.prefix(12)) { activity in
                        HStack(spacing: 8) {
                            Text(activity.timestamp.formatted(date: .omitted, time: .standard))
                                .monospacedDigit()
                                .foregroundStyle(PoolDashboardTheme.textMuted)
                                .frame(width: 104, alignment: .leading)
                            Text(activity.message)
                                .foregroundStyle(PoolDashboardTheme.textPrimary)
                        }
                        .dashboardListRowCard()
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: PoolDashboardTheme.activityListMinHeight)
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }
}
