import SwiftUI
import WidgetKit

private struct WidgetBridgeSnapshot: Codable {
    let updatedAt: Date
    let status: String
    let source: String
    let mode: String?
    let totalAccounts: Int?
    let availableAccounts: Int?
    let overallUsagePercent: Int?
    let activeAccountName: String?
}

private enum WidgetBridgeSnapshotStore {
    static let bridgeURL = URL(string: "http://127.0.0.1:38477/widget-snapshot")!
    static let requestTimeout: TimeInterval = 0.5

    static func load() -> WidgetBridgeSnapshot? {
        var request = URLRequest(url: bridgeURL)
        request.timeoutInterval = requestTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = requestTimeout
        sessionConfiguration.timeoutIntervalForResource = requestTimeout

        let semaphore = DispatchSemaphore(value: 0)
        var resolvedSnapshot: WidgetBridgeSnapshot?

        let task = URLSession(configuration: sessionConfiguration).dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data,
                  !data.isEmpty else {
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            resolvedSnapshot = try? decoder.decode(WidgetBridgeSnapshot.self, from: data)
        }

        task.resume()
        _ = semaphore.wait(timeout: .now() + requestTimeout)
        return resolvedSnapshot
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
                if let activeAccountName = snapshot.activeAccountName {
                    Text("Active: \(activeAccountName)")
                }
                if let mode = snapshot.mode {
                    Text("Mode: \(mode.capitalized)")
                }
                if let totalAccounts = snapshot.totalAccounts,
                   let availableAccounts = snapshot.availableAccounts {
                    Text("Available: \(availableAccounts)/\(totalAccounts)")
                }
                if let overallUsagePercent = snapshot.overallUsagePercent {
                    Text("Overall Usage: \(overallUsagePercent)%")
                }
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
