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
        guard var root = jsonObject as? [String: Any],
              var accounts = root["accounts"] as? [[String: Any]] else {
            throw CocoaError(.fileWriteUnknown)
        }

        for index in accounts.indices where index < exportSnapshot.accounts.count {
            let account = exportSnapshot.accounts[index]
            let canRefetchUsage = !account.apiToken.isEmpty && !(account.chatGPTAccountID?.isEmpty ?? true)
            if canRefetchUsage {
                accounts[index].removeValue(forKey: "quota")
                accounts[index].removeValue(forKey: "usedUnits")
                accounts[index].removeValue(forKey: "usageWindowName")
                accounts[index].removeValue(forKey: "usageWindowResetAt")
            }
        }

        root["accounts"] = accounts
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
        let normalizedAccounts = snapshot.accounts.map { account in
            let canRefetchUsage = !account.apiToken.isEmpty && !(account.chatGPTAccountID?.isEmpty ?? true)
            guard canRefetchUsage else { return account }

            return AgentAccount(
                id: account.id,
                name: account.name,
                groupName: account.groupName,
                usedUnits: 0,
                quota: 100,
                apiToken: account.apiToken,
                email: account.email,
                chatGPTAccountID: account.chatGPTAccountID,
                usageWindowName: nil,
                usageWindowResetAt: nil
            )
        }

        return AccountPoolSnapshot(
            accounts: normalizedAccounts,
            groups: snapshot.groups,
            activities: snapshot.activities,
            mode: snapshot.mode,
            activeAccountID: snapshot.activeAccountID,
            manualAccountID: snapshot.manualAccountID,
            focusLockedAccountID: snapshot.focusLockedAccountID,
            minSwitchInterval: snapshot.minSwitchInterval,
            lowUsageThresholdRatio: snapshot.lowUsageThresholdRatio,
            lowUsageAlertThresholdRatio: snapshot.lowUsageAlertThresholdRatio,
            minUsageRatioDeltaToSwitch: snapshot.minUsageRatioDeltaToSwitch,
            lastSwitchAt: snapshot.lastSwitchAt,
            lastUsageSyncAt: snapshot.lastUsageSyncAt,
            switchWithoutLaunching: snapshot.switchWithoutLaunching,
            autoSyncEnabled: snapshot.autoSyncEnabled,
            autoSyncIntervalSeconds: snapshot.autoSyncIntervalSeconds
        )
    }
}
