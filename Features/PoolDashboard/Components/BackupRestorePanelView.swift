import SwiftUI
import AppKit
import UniformTypeIdentifiers

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

                sensitiveCalloutRow

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

    private var sensitiveCalloutRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                PanelStatusCalloutView(
                    message: L10n.text("backup_restore.sensitive.message"),
                    title: L10n.text("backup_restore.sensitive.title"),
                    tone: .warning
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    clearButton
                    saveButton
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 8) {
                PanelStatusCalloutView(
                    message: L10n.text("backup_restore.sensitive.message"),
                    title: L10n.text("backup_restore.sensitive.title"),
                    tone: .warning
                )

                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    clearButton
                    saveButton
                }
            }
        }
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

    private var clearButton: some View {
        Button(L10n.text("common.clear")) {
            backupJSON = ""
            backupError = nil
        }
        .buttonStyle(DashboardSubtleButtonStyle())
        .disabled(backupJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var saveButton: some View {
        Button(L10n.text("account.edit.save")) {
            saveBackupJSONToFile()
        }
        .buttonStyle(DashboardPrimaryButtonStyle())
        .disabled(backupJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func saveBackupJSONToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "codex-pool-backup.json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try Data(backupJSON.utf8).write(to: url, options: .atomic)
            backupError = nil
        } catch {
            backupError = error.localizedDescription
        }
    }
}
