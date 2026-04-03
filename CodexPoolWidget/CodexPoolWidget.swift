import WidgetKit
import SwiftUI

struct WidgetBridgeSnapshot: Codable {
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
}

private enum WidgetBridgeSnapshotStore {
    static let bridgeURL = URL(string: "http://127.0.0.1:38477/widget-snapshot")!
    static let requestTimeout: TimeInterval = 0.35

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

struct CodexPoolWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetBridgeSnapshot?
}

struct CodexPoolWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexPoolWidgetEntry {
        CodexPoolWidgetEntry(
            date: Date(),
            snapshot: WidgetBridgeSnapshot(
                updatedAt: Date(),
                status: "Loading status...",
                source: "CodexPoolManager",
                mode: "intelligent",
                totalAccounts: 0,
                availableAccounts: 0,
                overallUsagePercent: 0,
                activeAccountName: nil,
                activeIsPaid: nil,
                activeRemainingUnits: nil,
                activeQuota: nil,
                activeFiveHourRemainingPercent: nil
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexPoolWidgetEntry) -> Void) {
        completion(
            CodexPoolWidgetEntry(
                date: Date(),
                snapshot: WidgetBridgeSnapshotStore.load()
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexPoolWidgetEntry>) -> Void) {
        let currentDate = Date()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)
            ?? currentDate.addingTimeInterval(900)

        let entry = CodexPoolWidgetEntry(
            date: currentDate,
            snapshot: WidgetBridgeSnapshotStore.load()
        )
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct CodexPoolWidgetEntryView: View {
    let entry: CodexPoolWidgetProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Codex Pool")
                    .font(.headline)
                Spacer(minLength: 8)
                Text(entry.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let snapshot = entry.snapshot {
                if let totalAccounts = snapshot.totalAccounts,
                   let availableAccounts = snapshot.availableAccounts,
                   let overallUsagePercent = snapshot.overallUsagePercent {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Available")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(availableAccounts)/\(totalAccounts)")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Usage")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(overallUsagePercent)%")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                }

                if let activeAccountName = snapshot.activeAccountName, !activeAccountName.isEmpty {
                    Text(activeAccountName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                } else {
                    Text(snapshot.status)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }

                if snapshot.activeIsPaid == true {
                    Text("Plan: Paid")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let weeklyRemaining = snapshot.activeRemainingUnits {
                        if let weeklyQuota = snapshot.activeQuota, weeklyQuota > 0 {
                            Text("Weekly left: \(weeklyRemaining)/\(weeklyQuota)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .monospacedDigit()
                        } else {
                            Text("Weekly left: \(weeklyRemaining)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .monospacedDigit()
                        }
                    }
                    if let fiveHourRemaining = snapshot.activeFiveHourRemainingPercent {
                        Text("5h left: \(fiveHourRemaining)%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .monospacedDigit()
                    }
                } else if let activeRemainingUnits = snapshot.activeRemainingUnits {
                    if let activeQuota = snapshot.activeQuota, activeQuota > 0 {
                        Text("Remaining: \(activeRemainingUnits)/\(activeQuota)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .monospacedDigit()
                    } else {
                        Text("Remaining: \(activeRemainingUnits)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .monospacedDigit()
                    }
                }

                if let mode = snapshot.mode, !mode.isEmpty {
                    Text("Mode: \(mode.capitalized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(snapshot.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("Updated \(snapshot.updatedAt, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No snapshot available")
                    .font(.subheadline.weight(.semibold))

                Text("Open CodexPoolManager once")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct CodexPoolWidget: Widget {
    private let kind = "CodexPoolWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexPoolWidgetProvider()) { entry in
            CodexPoolWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Codex Pool Status")
        .description("Quick view for Codex Pool Manager.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CodexPoolWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodexPoolWidget()
    }
}
