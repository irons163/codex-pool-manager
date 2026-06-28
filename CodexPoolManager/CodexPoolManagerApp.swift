//
//  CodexPoolManagerApp.swift
//  CodexPoolManager
//
//  Created by Phil on 2026/3/24.
//

import SwiftUI
import AppKit

@main
struct CodexPoolManagerApp: App {
    @AppStorage(L10n.languageOverrideKey) private var appLanguageOverride = L10n.systemLanguageCode
    @StateObject private var runtimeModel: AppPoolRuntimeModel
    @Environment(\.openWindow) private var openWindow
    
    init() {
        let defaults = AppRuntimeStorage.defaults
        LegacySandboxPreferencesMigrator.migrateIfNeeded(defaults: defaults)
        PreferenceValueNormalizer.normalizeIfNeeded(defaults: defaults)
        _runtimeModel = StateObject(wrappedValue: AppPoolRuntimeModel())
        if !AppRuntimeStorage.isRunningXCTest {
            WidgetBridgePublisher.configureBridge()
            WidgetBridgePublisher.publishFromMainApp(status: "Codex Pool Manager is running")
        }
    }

    var body: some Scene {
        WindowGroup("Dashboard", id: "dashboard") {
            ContentView(runtimeModel: runtimeModel)
                .id(appLanguageOverride)
                .environment(\.locale, L10n.locale(for: appLanguageOverride))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            SidebarCommands()
        }

        MenuBarExtra {
            MenuBarDashboardView(
                runtimeModel: runtimeModel,
                openDashboard: {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                },
                switchAccount: { accountID in
                    Task { @MainActor in
                        await runtimeModel.switchAccount(accountID)
                    }
                }
            )
            .id(appLanguageOverride)
            .environment(\.locale, L10n.locale(for: appLanguageOverride))
            .task {
                runtimeModel.bootstrapIfNeeded()
            }
        } label: {
            Text(runtimeModel.menuBarSnapshot.title)
                .monospacedDigit()
                .task {
                    runtimeModel.bootstrapIfNeeded()
                }
        }
        .menuBarExtraStyle(.window)
    }
}

enum AppRuntimeStorage {
    static var isRunningXCTest: Bool {
        isRunningTestEnvironment()
    }

    // Detects both XCTest and Swift Testing. The app must never operate on the
    // user's real preferences while under test. Checking only
    // `XCTestConfigurationFilePath` misses Swift Testing, which is how the real
    // token vault once got wiped by a test host booting against `.standard`.
    static func isRunningTestEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let testEnvKeys = [
            "XCTestConfigurationFilePath",
            "XCTestBundlePath",
            "XCTestSessionIdentifier"
        ]
        if testEnvKeys.contains(where: { environment[$0] != nil }) {
            return true
        }
        if let injected = environment["DYLD_INSERT_LIBRARIES"],
           injected.contains("XCTest") || injected.contains(".xctest") {
            return true
        }
        if Bundle.allBundles.contains(where: { $0.bundlePath.hasSuffix(".xctest") }) {
            return true
        }
        if NSClassFromString("XCTestCase") != nil {
            return true
        }
        return false
    }

    static var defaults: UserDefaults {
        testingDefaults ?? .standard
    }

    static var accountPoolStore: DeveloperAwareAccountPoolStore {
        DeveloperAwareAccountPoolStore(defaults: defaults)
    }

    private static let testingDefaults: UserDefaults? = {
        guard isRunningXCTest else { return nil }
        let suiteName = "CodexPoolManager.AppHostTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }()
}

private enum LegacySandboxPreferencesMigrator {
    private static let migrationMarkerKey = "did_migrate_sandbox_preferences_v1"
    private static let snapshotKey = "account_pool_snapshot"
    private static let tokenKey = "account_pool_tokens"
    private static let legacyPreferencesPath =
        "Library/Containers/com.irons.CodexPoolManager/Data/Library/Preferences/com.irons.CodexPoolManager.plist"

    static func migrateIfNeeded(
        defaults: UserDefaults = .standard,
        legacyPreferencesOverride: [String: Any]? = nil
    ) {
        guard !defaults.bool(forKey: migrationMarkerKey) else { return }

        let legacyPreferences: [String: Any]
        if let legacyPreferencesOverride {
            legacyPreferences = legacyPreferencesOverride
        } else {
            let legacyURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(legacyPreferencesPath)
            guard FileManager.default.fileExists(atPath: legacyURL.path),
                  let loaded = NSDictionary(contentsOf: legacyURL) as? [String: Any]
            else {
                defaults.set(true, forKey: migrationMarkerKey)
                return
            }
            legacyPreferences = loaded
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

private enum PreferenceValueNormalizer {
    static func normalizeIfNeeded(defaults: UserDefaults = .standard) {
        let normalizedAppearance = AppAppearancePreference.normalizedRawValue(
            defaults.string(forKey: AppAppearancePreference.storageKey) ?? ""
        )
        if defaults.string(forKey: AppAppearancePreference.storageKey) != normalizedAppearance {
            defaults.set(normalizedAppearance, forKey: AppAppearancePreference.storageKey)
        }

        let normalizedLanguage = L10n.normalizedLanguageOverrideCode(
            defaults.string(forKey: L10n.languageOverrideKey) ?? L10n.systemLanguageCode
        )
        if defaults.string(forKey: L10n.languageOverrideKey) != normalizedLanguage {
            defaults.set(normalizedLanguage, forKey: L10n.languageOverrideKey)
        }
    }
}

struct MenuBarBridgeSnapshot: Codable {
    let updatedAt: Date
    let activeAccountName: String?
    let activeIsPaid: Bool?
    let activeRemainingUnits: Int?
    let activeQuota: Int?
    let activeFiveHourRemainingPercent: Int?
    let activeWeeklyResetAt: Date?
    let activeFiveHourResetAt: Date?
}

enum MenuBarSnapshotFormatter {
    static func menuBarTitle(
        snapshot: MenuBarBridgeSnapshot?,
        now: Date = Date()
    ) -> String {
        guard let snapshot else { return "Codex --" }

        var segments: [String] = []

        if snapshot.activeIsPaid == true,
           let remaining = snapshot.activeRemainingUnits,
           let quota = snapshot.activeQuota,
           quota > 0 {
            let ratio = Double(remaining) / Double(quota)
            let weeklyRemainingPercent = max(0, min(100, Int((ratio * 100).rounded())))
            segments.append("w \(weeklyRemainingPercent)%")
        } else if let remaining = snapshot.activeRemainingUnits,
                  let quota = snapshot.activeQuota,
                  quota > 0 {
            let ratio = Double(remaining) / Double(quota)
            let remainingPercent = max(0, min(100, Int((ratio * 100).rounded())))
            segments.append("\(remainingPercent)%")
        } else if let remaining = snapshot.activeRemainingUnits {
            segments.append("\(remaining)")
        } else {
            segments.append("--")
        }

        if snapshot.activeIsPaid == true,
           let fiveHourLeft = snapshot.activeFiveHourRemainingPercent {
            segments.append("5h \(fiveHourLeft)%")
        }

        segments.append(shortAgeText(since: snapshot.updatedAt, now: now))

        return "Codex " + segments.joined(separator: " · ")
    }

    static func shortAgeText(
        since date: Date,
        now: Date = Date()
    ) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 10 { return "now" }
        if seconds < 60 { return "\(seconds)s" }

        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }

        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }

        let days = hours / 24
        return "\(days)d"
    }
}

#if DEBUG
extension CodexPoolManagerApp {
    static func debugRunLegacyMigration(
        defaults: UserDefaults,
        legacyPreferences: [String: Any]?
    ) {
        LegacySandboxPreferencesMigrator.migrateIfNeeded(
            defaults: defaults,
            legacyPreferencesOverride: legacyPreferences
        )
    }

    static func debugNormalizePreferences(defaults: UserDefaults) {
        PreferenceValueNormalizer.normalizeIfNeeded(defaults: defaults)
    }

    static func debugMenuBarTitle(snapshot: MenuBarBridgeSnapshot?, now: Date = Date()) -> String {
        MenuBarSnapshotFormatter.menuBarTitle(snapshot: snapshot, now: now)
    }
}
#endif
