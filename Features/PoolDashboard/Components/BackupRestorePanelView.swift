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

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: PoolDashboardTheme.actionRowSpacing) {
                        exportButton
                        exportRefetchableButton
                        importButton
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: PoolDashboardTheme.actionRowSpacing) {
                            exportButton
                            exportRefetchableButton
                        }
                        importButton
                    }
                }

                PanelStatusCalloutView(
                    message: "Refetchable exports may include access token and account id. Store only in secure internal systems.",
                    title: "Sensitive Material",
                    tone: .warning
                )

                TextEditor(text: $backupJSON)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: PoolDashboardTheme.backupEditorMinHeight)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.editorCornerRadius, style: .continuous)
                            .fill(PoolDashboardTheme.panelMutedFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: PoolDashboardTheme.editorCornerRadius, style: .continuous)
                                    .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: 1)
                            )
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
    }

    private var exportRefetchableButton: some View {
        Button("Export Refetchable", action: onExportRefetchable)
            .buttonStyle(DashboardWarningButtonStyle())
    }

    private var importButton: some View {
        Button("Import JSON", action: onImport)
            .buttonStyle(DashboardPrimaryButtonStyle())
    }
}
