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
    let activeIsPaid: Bool?
    let activeRemainingUnits: Int?
    let activeQuota: Int?
    let activeFiveHourRemainingPercent: Int?
    let activeWeeklyResetAt: Date?
    let activeFiveHourResetAt: Date?
}

private enum WidgetHostLocaleResolver {
    private static let languageOverrideKey = "app_language_override"
    private static let systemLanguageCode = "system"
    private static let supportedLanguageCodes = ["en", "zh-Hant", "zh-Hans", "fr", "es", "ja", "ko"]

    static func currentLocale() -> Locale {
        guard let overrideCode = UserDefaults.standard.string(forKey: languageOverrideKey),
              overrideCode != systemLanguageCode,
              supportedLanguageCodes.contains(overrideCode) else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: overrideCode)
    }
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
    private let displayLocale = WidgetHostLocaleResolver.currentLocale()

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
                if snapshot.activeIsPaid == true {
                    Text("Plan: Paid")
                    if let weeklyRemaining = snapshot.activeRemainingUnits {
                        if let weeklyQuota = snapshot.activeQuota, weeklyQuota > 0 {
                            Text("Weekly left: \(weeklyRemaining)/\(weeklyQuota)")
                        } else {
                            Text("Weekly left: \(weeklyRemaining)")
                        }
                    }
                    if let fiveHourRemaining = snapshot.activeFiveHourRemainingPercent {
                        Text("5h left: \(fiveHourRemaining)%")
                    }
                    Text(
                        "Weekly reset: \(snapshot.activeWeeklyResetAt.map(localizedAbbreviatedDateTimeText) ?? "--")"
                    )
                    Text(
                        "5h reset: \(snapshot.activeFiveHourResetAt.map(localizedAbbreviatedDateTimeText) ?? "--")"
                    )
                } else if let activeRemainingUnits = snapshot.activeRemainingUnits {
                    if let activeQuota = snapshot.activeQuota, activeQuota > 0 {
                        Text("Remaining: \(activeRemainingUnits)/\(activeQuota)")
                    } else {
                        Text("Remaining: \(activeRemainingUnits)")
                    }
                    if let resetAt = snapshot.activeWeeklyResetAt {
                        Text("Reset: \(localizedAbbreviatedDateTimeText(resetAt))")
                    }
                }
                if let totalAccounts = snapshot.totalAccounts,
                   let availableAccounts = snapshot.availableAccounts {
                    Text("Available: \(availableAccounts)/\(totalAccounts)")
                }
                Text("Updated: \(localizedAbbreviatedDateTimeText(snapshot.updatedAt))")
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
        .environment(\.locale, displayLocale)
        .onAppear {
            snapshot = WidgetBridgeSnapshotStore.load()
        }
    }

    private func localizedAbbreviatedDateTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    ContentView()
}
