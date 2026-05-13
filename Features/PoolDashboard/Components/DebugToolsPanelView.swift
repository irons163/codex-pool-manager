import SwiftUI

struct DebugDiagnosticMetric: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
}

struct DebugToolsPanelView: View {
    @Binding var showUsageRawJSON: Bool
    @Binding var lastUsageRawJSON: String
    @Binding var showSwitchLaunchLog: Bool
    @Binding var lastSwitchLaunchLog: String
    let diagnostics: [DebugDiagnosticMetric]

    var body: some View {
        GroupBox(L10n.text("debug_tools.title")) {
            VStack(alignment: .leading, spacing: 12) {
                PanelStatusCalloutView(
                    message: L10n.text("debug_tools.warning.message"),
                    title: L10n.text("debug_tools.warning.title"),
                    tone: .warning
                )

                if !diagnostics.isEmpty {
                    diagnosticsGrid
                }

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

    private var diagnosticsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("debug_tools.memory_storage"))
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(diagnostics) { metric in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(metric.title)
                            .font(.caption)
                            .foregroundStyle(PoolDashboardTheme.textMuted)
                        Text(metric.value)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(PoolDashboardTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(PoolDashboardTheme.panelFill.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
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
