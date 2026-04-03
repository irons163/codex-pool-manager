//
//  CodexPoolManagerApp.swift
//  CodexPoolManager
//
//  Created by Phil on 2026/3/24.
//

import SwiftUI
import AppKit
import Combine

@main
struct CodexPoolManagerApp: App {
    @AppStorage(L10n.languageOverrideKey) private var appLanguageOverride = L10n.systemLanguageCode
    @StateObject private var menuBarModel = MenuBarSnapshotModel()
    
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

        MenuBarExtra {
            MenuBarStatusMenuView(model: menuBarModel)
        } label: {
            Text(menuBarModel.menuBarTitle)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.menu)
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

private struct MenuBarBridgeSnapshot: Codable {
    let updatedAt: Date
    let activeAccountName: String?
    let activeIsPaid: Bool?
    let activeRemainingUnits: Int?
    let activeQuota: Int?
    let activeFiveHourRemainingPercent: Int?
    let activeWeeklyResetAt: Date?
    let activeFiveHourResetAt: Date?
}

@MainActor
private final class MenuBarSnapshotModel: ObservableObject {
    @Published private(set) var snapshot: MenuBarBridgeSnapshot?

    private var timer: Timer?

    var menuBarTitle: String {
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

        segments.append(shortAgeText(since: snapshot.updatedAt))

        return "Codex " + segments.joined(separator: " · ")
    }

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        Task {
            let latest = await Self.fetchSnapshot()
            if let latest {
                snapshot = latest
            }
        }
    }

    private static func fetchSnapshot() async -> MenuBarBridgeSnapshot? {
        guard let url = URL(string: "http://127.0.0.1:38477/widget-snapshot") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.0
        configuration.timeoutIntervalForResource = 1.0

        do {
            let (data, response) = try await URLSession(configuration: configuration).data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  !data.isEmpty else {
                return nil
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(MenuBarBridgeSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    private func shortAgeText(since date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
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

private struct MenuBarStatusMenuView: View {
    @ObservedObject var model: MenuBarSnapshotModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let snapshot = model.snapshot {
                if let accountName = snapshot.activeAccountName, !accountName.isEmpty {
                    Text(accountName)
                        .font(.headline)
                        .lineLimit(1)
                } else {
                    Text("No active account")
                        .font(.headline)
                }

                if let remaining = snapshot.activeRemainingUnits,
                   let quota = snapshot.activeQuota,
                   quota > 0 {
                    Text("Remaining: \(remaining)/\(quota)")
                        .monospacedDigit()
                } else if let remaining = snapshot.activeRemainingUnits {
                    Text("Remaining: \(remaining)")
                        .monospacedDigit()
                }

                if snapshot.activeIsPaid == true {
                    if let fiveHourLeft = snapshot.activeFiveHourRemainingPercent {
                        Text("5h left: \(fiveHourLeft)%")
                            .monospacedDigit()
                    }
                    Text("Weekly reset: \(formatDate(snapshot.activeWeeklyResetAt))")
                    Text("5h reset: \(formatDate(snapshot.activeFiveHourResetAt))")
                } else {
                    Text("Reset: \(formatDate(snapshot.activeWeeklyResetAt))")
                }

                Text("Updated \(snapshot.updatedAt, style: .relative)")
                    .foregroundStyle(.secondary)
            } else {
                Text("No snapshot available")
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Refresh") {
                model.refresh()
            }
            Button("Open CodexPoolManager") {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .padding(.vertical, 2)
        .frame(minWidth: 280, alignment: .leading)
    }

    private func formatDate(_ value: Date?) -> String {
        guard let value else { return "--" }
        return value.formatted(.dateTime.month().day().hour().minute())
    }
}
