import SwiftUI

struct BackupRestorePanelView: View {
    @Binding var backupJSON: String
    @Binding var backupError: String?

    let onExport: () -> Void
    let onExportRefetchable: () -> Void
    let onImport: () -> Void

    var body: some View {
        GroupBox("備份與還原") {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        exportButton
                        exportRefetchableButton
                        importButton
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            exportButton
                            exportRefetchableButton
                        }
                        importButton
                    }
                }

                Text("警告：匯出（可重抓）會包含 access token 與 account id，僅限你自己保管，勿分享。")
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.warning)
                    .calloutCard(fill: PoolDashboardTheme.warning.opacity(0.16))

                TextEditor(text: $backupJSON)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 190)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(PoolDashboardTheme.panelMutedFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: 1)
                            )
                    )

                if let backupError {
                    Text(backupError)
                        .statusBadge(tone: PoolDashboardTheme.danger.opacity(0.24))
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }

    private var exportButton: some View {
        Button("匯出 JSON", action: onExport)
            .buttonStyle(DashboardSubtleButtonStyle())
    }

    private var exportRefetchableButton: some View {
        Button("匯出（可重抓）", action: onExportRefetchable)
            .buttonStyle(DashboardWarningButtonStyle())
    }

    private var importButton: some View {
        Button("匯入 JSON", action: onImport)
            .buttonStyle(DashboardPrimaryButtonStyle())
    }
}
