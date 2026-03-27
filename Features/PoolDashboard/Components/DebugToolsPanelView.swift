import SwiftUI

struct DebugToolsPanelView: View {
    @Binding var showUsageRawJSON: Bool
    @Binding var lastUsageRawJSON: String
    @Binding var showSwitchLaunchLog: Bool
    @Binding var lastSwitchLaunchLog: String

    var body: some View {
        GroupBox("Debug Tools") {
            VStack(alignment: .leading, spacing: 12) {
                PanelStatusCalloutView(
                    message: "Use these tools only for diagnostics. Clear sensitive logs before sharing screenshots.",
                    title: "Debug Data Warning",
                    tone: .warning
                )

                debugDisclosure(
                    title: "Usage Raw JSON",
                    isExpanded: $showUsageRawJSON,
                    content: $lastUsageRawJSON,
                    emptyText: "No usage response captured yet.",
                    tint: PoolDashboardTheme.glowA
                )

                debugDisclosure(
                    title: "Switch Launch Log",
                    isExpanded: $showSwitchLaunchLog,
                    content: $lastSwitchLaunchLog,
                    emptyText: "No switch-and-launch operation executed yet.",
                    tint: PoolDashboardTheme.glowB
                )
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }

    private func debugDisclosure(
        title: String,
        isExpanded: Binding<Bool>,
        content: Binding<String>,
        emptyText: String,
        tint: Color
    ) -> some View {
        DisclosureGroup(title, isExpanded: isExpanded) {
            if content.wrappedValue.isEmpty {
                PanelStatusCalloutView(
                    message: emptyText,
                    title: "No Data",
                    tone: .info
                )
            } else {
                TextEditor(text: content)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: PoolDashboardTheme.debugEditorMinHeight)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.editorCornerRadius, style: .continuous)
                            .fill(PoolDashboardTheme.panelMutedFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: PoolDashboardTheme.editorCornerRadius, style: .continuous)
                                    .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: 1)
                            )
                    )

                HStack {
                    Button("Clear") {
                        content.wrappedValue = ""
                    }
                    .buttonStyle(DashboardWarningButtonStyle())
                    Spacer()
                }
            }
        }
        .tint(tint)
    }
}
