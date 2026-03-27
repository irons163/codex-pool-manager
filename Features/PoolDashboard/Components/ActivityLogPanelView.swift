import SwiftUI

struct ActivityLogPanelView: View {
    let activities: [PoolActivity]
    let onClearActivities: () -> Void

    var body: some View {
        GroupBox("Activity Feed") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Latest system actions and switch records.")
                        .font(.footnote)
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                    Spacer()
                    Text("\(activities.count)")
                        .statusBadge(tone: PoolDashboardTheme.panelMutedFill)
                }

                if activities.isEmpty {
                    Text("No activity yet.")
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                        .calloutCard(fill: PoolDashboardTheme.panelMutedFill, border: PoolDashboardTheme.panelInnerStroke)
                } else {
                    HStack {
                        Spacer()
                        Button("Clear Activity", role: .destructive) {
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
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: PoolDashboardTheme.controlCornerRadius, style: .continuous)
                                .fill(PoolDashboardTheme.panelMutedFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: PoolDashboardTheme.controlCornerRadius, style: .continuous)
                                        .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: 1)
                                )
                                .padding(.vertical, PoolDashboardTheme.listRowVerticalInset)
                        )
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
