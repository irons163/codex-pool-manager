import SwiftUI

struct SyncToolbarView: View {
    let isSyncing: Bool
    let lastSyncAt: Date?
    let errorText: String?
    let onSync: () -> Void

    var body: some View {
        HStack {
            Button(isSyncing ? "同步中..." : "同步 Codex 用量") {
                onSync()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSyncing)

            if let lastSyncAt {
                Text("最近同步：\(lastSyncAt, format: Date.FormatStyle(date: .omitted, time: .standard))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }
}
