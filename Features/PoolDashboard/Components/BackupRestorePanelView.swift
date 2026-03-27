import SwiftUI

struct BackupRestorePanelView: View {
    @Binding var backupJSON: String
    @Binding var backupError: String?

    let onExport: () -> Void
    let onExportRefetchable: () -> Void
    let onImport: () -> Void

    var body: some View {
        GroupBox("Backup & Restore") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Export snapshots for recovery and migration. Keep refetchable exports private.")
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                PanelAdaptiveActionRowView {
                    exportButton
                    exportRefetchableButton
                    importButton
                }

                PanelStatusCalloutView(
                    message: "Refetchable exports may include access token and account id. Store only in secure internal systems.",
                    title: "Sensitive Material",
                    tone: .warning
                )

                PanelCodeEditorView(
                    text: $backupJSON,
                    minimumHeight: PoolDashboardTheme.backupEditorMinHeight,
                    font: .system(.body, design: .monospaced)
                )

                if let backupError {
                    PanelStatusCalloutView(
                        message: backupError,
                        title: "Backup Operation Failed",
                        tone: .danger
                    )
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }

    private var exportButton: some View {
        Button("Export JSON", action: onExport)
            .buttonStyle(DashboardSubtleButtonStyle())
            .accessibilityIdentifier("backup.exportJsonButton")
    }

    private var exportRefetchableButton: some View {
        Button("Export Refetchable", action: onExportRefetchable)
            .buttonStyle(DashboardWarningButtonStyle())
    }

    private var importButton: some View {
        Button("Import JSON", action: onImport)
            .buttonStyle(DashboardPrimaryButtonStyle())
            .accessibilityIdentifier("backup.importJsonButton")
    }
}
