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
                            .foregroundStyle(.white.opacity(0.70))
                    } else {
                        TextEditor(text: $lastUsageRawJSON)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(minHeight: 120)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(PoolDashboardTheme.panelFill)
                            )
                        HStack {
                            Button("清除") {
                                lastUsageRawJSON = ""
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                        }
                    }
                }

                DisclosureGroup("Last Switch Launch Log", isExpanded: $showSwitchLaunchLog) {
                    if lastSwitchLaunchLog.isEmpty {
                        Text("尚未執行切換並啟動")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.70))
                    } else {
                        TextEditor(text: $lastSwitchLaunchLog)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(minHeight: 120)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(PoolDashboardTheme.panelFill)
                            )
                        HStack {
                            Button("清除") {
                                lastSwitchLaunchLog = ""
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                        }
                    }
                }
            }
        }
        .tint(PoolDashboardTheme.glowA)
    }
}
