import SwiftUI

struct BackupRestorePanelView: View {
    @Binding var backupJSON: String
    @Binding var backupError: String?

    let onExport: () -> Void
    let onExportRefetchable: () -> Void
    let onImport: () -> Void

    var body: some View {
        GroupBox("備份與還原") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button("匯出 JSON") {
                        onExport()
                    }
                    .buttonStyle(.bordered)
                    .tint(PoolDashboardTheme.glowA)

                    Button("匯出（可重抓）") {
                        onExportRefetchable()
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)

                    Button("匯入 JSON") {
                        onImport()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PoolDashboardTheme.glowB)
                }

                Text("警告：匯出（可重抓）會包含 access token 與 account id，僅限你自己保管，勿分享。")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.orange.opacity(0.16))
                    )

                TextEditor(text: $backupJSON)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(PoolDashboardTheme.panelFill)
                    )

                if let backupError {
                    Text(backupError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .tint(PoolDashboardTheme.glowA)
    }
}
