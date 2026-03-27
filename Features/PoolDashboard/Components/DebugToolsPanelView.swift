import SwiftUI

struct DebugToolsPanelView: View {
    @Binding var showUsageRawJSON: Bool
    @Binding var lastUsageRawJSON: String
    @Binding var showSwitchLaunchLog: Bool
    @Binding var lastSwitchLaunchLog: String

    var body: some View {
        GroupBox("Debug") {
            VStack(alignment: .leading, spacing: 10) {
                DisclosureGroup("Last Usage Raw JSON", isExpanded: $showUsageRawJSON) {
                    if lastUsageRawJSON.isEmpty {
                        Text("尚未捕捉到 usage response")
                            .font(.footnote)
                            .foregroundStyle(PoolDashboardTheme.textSecondary)
                    } else {
                        TextEditor(text: $lastUsageRawJSON)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(minHeight: 120)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(PoolDashboardTheme.panelMutedFill)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: 1)
                                    )
                            )
                        HStack {
                            Button("清除") {
                                lastUsageRawJSON = ""
                            }
                            .buttonStyle(DashboardWarningButtonStyle())
                            Spacer()
                        }
                    }
                }
                .tint(PoolDashboardTheme.glowA)

                DisclosureGroup("Last Switch Launch Log", isExpanded: $showSwitchLaunchLog) {
                    if lastSwitchLaunchLog.isEmpty {
                        Text("尚未執行切換並啟動")
                            .font(.footnote)
                            .foregroundStyle(PoolDashboardTheme.textSecondary)
                    } else {
                        TextEditor(text: $lastSwitchLaunchLog)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(minHeight: 120)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(PoolDashboardTheme.panelMutedFill)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: 1)
                                    )
                            )
                        HStack {
                            Button("清除") {
                                lastSwitchLaunchLog = ""
                            }
                            .buttonStyle(DashboardWarningButtonStyle())
                            Spacer()
                        }
                    }
                }
                .tint(PoolDashboardTheme.glowB)
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }
}
