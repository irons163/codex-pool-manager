import Foundation

enum AccountPoolSnapshotCodec {
    static func exportJSON(
        _ snapshot: AccountPoolSnapshot,
        redactSensitive: Bool = true
    ) throws -> String {
        let exportSnapshot: AccountPoolSnapshot
        if redactSensitive {
            exportSnapshot = snapshot.redactingAPITokens()
        } else {
            exportSnapshot = snapshot
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let encodedData = try encoder.encode(exportSnapshot)

        let jsonObject = try JSONSerialization.jsonObject(with: encodedData)
        guard var root = jsonObject as? [String: Any] else {
            throw CocoaError(.fileWriteUnknown)
        }

        root.removeValue(forKey: "activities")
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return json
    }

    static func importJSON(_ json: String) throws -> AccountPoolSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(json.utf8)
        let snapshot = try decoder.decode(AccountPoolSnapshot.self, from: data)
        return prepareForUsageRefetch(snapshot)
    }

    static func prepareForUsageRefetch(_ snapshot: AccountPoolSnapshot) -> AccountPoolSnapshot {
        snapshot
    }
}
