import Foundation

enum WidgetBridgePublisher {
    static let appGroupIdentifier = "group.com.irons.codexpoolbridge"
    static let snapshotFileName = "snapshot.json"

    struct Snapshot: Codable {
        let updatedAt: Date
        let status: String
        let source: String
    }

    static func publishFromMainApp(status: String) {
        let snapshot = Snapshot(
            updatedAt: Date(),
            status: status,
            source: "CodexPoolManager"
        )

        do {
            let groupDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Group Containers/\(appGroupIdentifier)", isDirectory: true)

            try FileManager.default.createDirectory(
                at: groupDirectory,
                withIntermediateDirectories: true
            )

            let snapshotURL = groupDirectory.appendingPathComponent(snapshotFileName)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(snapshot)
            try data.write(to: snapshotURL, options: .atomic)
        } catch {
            NSLog("WidgetBridgePublisher failed: \(error.localizedDescription)")
        }
    }
}
