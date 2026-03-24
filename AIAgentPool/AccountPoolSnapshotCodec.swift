import Foundation

enum AccountPoolSnapshotCodec {
    static func exportJSON(_ snapshot: AccountPoolSnapshot) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return json
    }

    static func importJSON(_ json: String) throws -> AccountPoolSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(json.utf8)
        return try decoder.decode(AccountPoolSnapshot.self, from: data)
    }
}
