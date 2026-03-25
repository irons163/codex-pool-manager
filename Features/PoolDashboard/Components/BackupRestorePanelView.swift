import SwiftUI

struct BackupRestorePanelView: View {
    @Binding var backupJSON: String
    @Binding var backupError: String?

    let onExport: () -> Void
    let onExportRefetchable: () -> Void
    let onImport: () -> Void

    var body: some View {
        GroupBox("備份與還原") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("匯出 JSON") {
                        onExport()
                    }
                    .buttonStyle(.bordered)

                    Button("匯出（可重抓）") {
                        onExportRefetchable()
                    }
                    .buttonStyle(.bordered)

                    Button("匯入 JSON") {
                        onImport()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text("警告：匯出（可重抓）會包含 access token 與 account id，僅限你自己保管，勿分享。")
                    .font(.footnote)
                    .foregroundStyle(.orange)

                TextEditor(text: $backupJSON)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)

                if let backupError {
                    Text(backupError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
