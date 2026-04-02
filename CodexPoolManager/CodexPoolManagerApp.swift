//
//  CodexPoolManagerApp.swift
//  CodexPoolManager
//
//  Created by Phil on 2026/3/24.
//

import SwiftUI

@main
struct CodexPoolManagerApp: App {
    @AppStorage(L10n.languageOverrideKey) private var appLanguageOverride = L10n.systemLanguageCode
    
    init() {
        LegacySandboxPreferencesMigrator.migrateIfNeeded()
        WidgetBridgePublisher.configureBridge()
        WidgetBridgePublisher.publishFromMainApp(status: "Codex Pool Manager is running")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(appLanguageOverride)
                .environment(\.locale, L10n.locale(for: appLanguageOverride))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            SidebarCommands()
        }
    }
}

private enum LegacySandboxPreferencesMigrator {
    private static let migrationMarkerKey = "did_migrate_sandbox_preferences_v1"
    private static let snapshotKey = "account_pool_snapshot"
    private static let tokenKey = "account_pool_tokens"
    private static let legacyPreferencesPath =
        "Library/Containers/com.irons.CodexPoolManager/Data/Library/Preferences/com.irons.CodexPoolManager.plist"

    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migrationMarkerKey) else { return }

        let legacyURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(legacyPreferencesPath)
        guard let legacyPreferences = NSDictionary(contentsOf: legacyURL) as? [String: Any] else {
            defaults.set(true, forKey: migrationMarkerKey)
            return
        }

        var migrated = false

        if let legacyTokens = legacyPreferences[tokenKey] as? [String: String] {
            var currentTokens = defaults.dictionary(forKey: tokenKey) as? [String: String] ?? [:]
            for (accountID, token) in legacyTokens where !token.isEmpty {
                if currentTokens[accountID]?.isEmpty != false {
                    currentTokens[accountID] = token
                    migrated = true
                }
            }
            if migrated {
                defaults.set(currentTokens, forKey: tokenKey)
            }
        }

        if defaults.data(forKey: snapshotKey) == nil,
           let legacySnapshot = legacyPreferences[snapshotKey] as? Data {
            defaults.set(legacySnapshot, forKey: snapshotKey)
            migrated = true
        }

        defaults.set(true, forKey: migrationMarkerKey)
        if migrated {
            NSLog("Migrated account pool preferences from sandbox container.")
        }
    }
}
