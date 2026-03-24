import Foundation

enum AccountPoolSnapshotCodec {
    static func exportJSON(
        _ snapshot: AccountPoolSnapshot,
        redactSensitive: Bool = true
    ) throws -> String {
        let exportSnapshot: AccountPoolSnapshot
        if redactSensitive {
            exportSnapshot = AccountPoolSnapshot(
                accounts: snapshot.accounts.map {
                    AgentAccount(
                        id: $0.id,
                        name: $0.name,
                        usedUnits: $0.usedUnits,
                        quota: $0.quota,
                        apiToken: ""
                    )
                },
                activities: snapshot.activities,
                mode: snapshot.mode,
                activeAccountID: snapshot.activeAccountID,
                manualAccountID: snapshot.manualAccountID,
                focusLockedAccountID: snapshot.focusLockedAccountID,
                minSwitchInterval: snapshot.minSwitchInterval,
                lowUsageThresholdRatio: snapshot.lowUsageThresholdRatio,
                minUsageRatioDeltaToSwitch: snapshot.minUsageRatioDeltaToSwitch,
                lastSwitchAt: snapshot.lastSwitchAt
            )
        } else {
            exportSnapshot = snapshot
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(exportSnapshot)
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
