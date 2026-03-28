import SwiftUI

struct BackupRestorePanelView: View {
    @Binding var backupJSON: String
    @Binding var backupError: String?

    let onExport: () -> Void
    let onExportRefetchable: () -> Void
    let onImport: () -> Void

    var body: some View {
        GroupBox(L10n.text("backup_restore.title")) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text("backup_restore.subtitle"))
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                PanelAdaptiveActionRowView {
                    exportButton
                    exportRefetchableButton
                    importButton
                }

                PanelStatusCalloutView(
                    message: L10n.text("backup_restore.sensitive.message"),
                    title: L10n.text("backup_restore.sensitive.title"),
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
                        title: L10n.text("backup_restore.failed"),
                        tone: .danger
                    )
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }

    private var exportButton: some View {
        Button(L10n.text("backup_restore.export_json"), action: onExport)
            .buttonStyle(DashboardSubtleButtonStyle())
            .accessibilityIdentifier("backup.exportJsonButton")
    }

    private var exportRefetchableButton: some View {
        Button(L10n.text("backup_restore.export_refetchable"), action: onExportRefetchable)
            .buttonStyle(DashboardWarningButtonStyle())
    }

    private var importButton: some View {
        Button(L10n.text("backup_restore.import_json"), action: onImport)
            .buttonStyle(DashboardPrimaryButtonStyle())
            .accessibilityIdentifier("backup.importJsonButton")
    }
}
