import SwiftUI
import WidgetKit

private struct WidgetBridgeSnapshot: Codable {
    let updatedAt: Date
    let status: String
    let source: String
}

private enum WidgetBridgeSnapshotStore {
    static let appGroupIdentifier = "group.com.irons.codexpoolbridge"
    static let snapshotFileName = "snapshot.json"

    static func load() -> WidgetBridgeSnapshot? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }

        let url = containerURL.appendingPathComponent(snapshotFileName)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetBridgeSnapshot.self, from: data)
    }
}

struct ContentView: View {
    @State private var snapshot = WidgetBridgeSnapshotStore.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Codex Pool Widget Host")
                .font(.title2.weight(.semibold))

            if let snapshot {
                Text("Status: \(snapshot.status)")
                Text("Source: \(snapshot.source)")
                Text("Updated: \(snapshot.updatedAt.formatted(date: .abbreviated, time: .standard))")
                    .foregroundStyle(.secondary)
            } else {
                Text("No snapshot found. Open CodexPoolManager once to publish data.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Reload Snapshot") {
                    snapshot = WidgetBridgeSnapshotStore.load()
                }

                Button("Refresh Widget") {
                    WidgetCenter.shared.reloadTimelines(ofKind: "CodexPoolWidget")
                }
            }
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 240, alignment: .topLeading)
        .onAppear {
            snapshot = WidgetBridgeSnapshotStore.load()
        }
    }
}

#Preview {
    ContentView()
}
