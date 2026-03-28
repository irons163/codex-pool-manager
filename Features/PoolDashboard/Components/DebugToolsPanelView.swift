import SwiftUI

struct DebugToolsPanelView: View {
    @Binding var showUsageRawJSON: Bool
    @Binding var lastUsageRawJSON: String
    @Binding var showSwitchLaunchLog: Bool
    @Binding var lastSwitchLaunchLog: String

    var body: some View {
        GroupBox(L10n.text("debug_tools.title")) {
            VStack(alignment: .leading, spacing: 12) {
                PanelStatusCalloutView(
                    message: L10n.text("debug_tools.warning.message"),
                    title: L10n.text("debug_tools.warning.title"),
                    tone: .warning
                )

                debugDisclosure(
                    title: L10n.text("debug_tools.usage_raw_json"),
                    isExpanded: $showUsageRawJSON,
                    content: $lastUsageRawJSON,
                    emptyText: L10n.text("debug_tools.usage_empty"),
                    tint: PoolDashboardTheme.glowA
                )

                debugDisclosure(
                    title: L10n.text("debug_tools.switch_launch_log"),
                    isExpanded: $showSwitchLaunchLog,
                    content: $lastSwitchLaunchLog,
                    emptyText: L10n.text("debug_tools.switch_empty"),
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
                    title: L10n.text("debug_tools.no_data"),
                    tone: .info
                )
            } else {
                PanelCodeEditorView(
                    text: content,
                    minimumHeight: PoolDashboardTheme.debugEditorMinHeight,
                    font: .system(.footnote, design: .monospaced)
                )

                HStack {
                    Button(L10n.text("common.clear")) {
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
