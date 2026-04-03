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
    let activeWeeklyResetAt: Date?
    let activeFiveHourResetAt: Date?
}

private enum WidgetBridgeSnapshotStore {
    static let bridgeURL = URL(string: "http://127.0.0.1:38477/widget-snapshot")!
    static let requestTimeout: TimeInterval = 1.0

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
                activeFiveHourRemainingPercent: nil,
                activeWeeklyResetAt: nil,
                activeFiveHourResetAt: nil
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
        let snapshot = WidgetBridgeSnapshotStore.load()
        let refreshInterval: TimeInterval = snapshot == nil ? 10 : 60
        let nextUpdate = currentDate.addingTimeInterval(refreshInterval)

        let entry = CodexPoolWidgetEntry(
            date: snapshot?.updatedAt ?? currentDate,
            snapshot: snapshot
        )
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct CodexPoolWidgetEntryView: View {
    let entry: CodexPoolWidgetProvider.Entry
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Codex Pool")
                    .font(.headline)
                Spacer(minLength: 8)
                if let snapshot = entry.snapshot {
                    Text("Updated \(snapshot.updatedAt, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(entry.date, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if let snapshot = entry.snapshot {
                if widgetFamily == .systemMedium {
                    mediumLayout(for: snapshot)
                } else {
                    compactLayout(for: snapshot)
                }
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

    @ViewBuilder
    private func mediumLayout(for snapshot: WidgetBridgeSnapshot) -> some View {
        if let activeAccountName = snapshot.activeAccountName, !activeAccountName.isEmpty {
            Text(activeAccountName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        } else {
            Text(snapshot.status)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }

        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if let totalAccounts = snapshot.totalAccounts,
                   let availableAccounts = snapshot.availableAccounts {
                    metricRow(title: "Available", value: "\(availableAccounts)/\(totalAccounts)", trailing: false)
                }
                if snapshot.activeIsPaid == true {
                    metricRow(title: "Plan", value: "Paid", trailing: false)
                }
                if let weeklyRemaining = snapshot.activeRemainingUnits {
                    if let weeklyQuota = snapshot.activeQuota, weeklyQuota > 0 {
                        metricRow(title: "Weekly left", value: "\(weeklyRemaining)/\(weeklyQuota)", trailing: false)
                    } else {
                        metricRow(title: "Remaining", value: "\(weeklyRemaining)", trailing: false)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                if snapshot.activeIsPaid == true {
                    metricRow(
                        title: "Weekly reset",
                        value: snapshot.activeWeeklyResetAt.map(formatResetTime) ?? "--",
                        trailing: true
                    )
                } else if let weeklyResetAt = snapshot.activeWeeklyResetAt {
                    metricRow(title: "Reset", value: formatResetTime(weeklyResetAt), trailing: true)
                }
                if let fiveHourRemaining = snapshot.activeFiveHourRemainingPercent {
                    metricRow(title: "5h left", value: "\(fiveHourRemaining)%", trailing: true)
                }
                if snapshot.activeIsPaid == true {
                    metricRow(
                        title: "5h reset",
                        value: snapshot.activeFiveHourResetAt.map(formatResetTime) ?? "--",
                        trailing: true
                    )
                }
                if let mode = snapshot.mode, !mode.isEmpty {
                    metricRow(title: "Mode", value: mode.capitalized, trailing: true)
                }
            }
        }

    }

    @ViewBuilder
    private func compactLayout(for snapshot: WidgetBridgeSnapshot) -> some View {
        if let totalAccounts = snapshot.totalAccounts,
           let availableAccounts = snapshot.availableAccounts {
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
            Text("Weekly reset: \(snapshot.activeWeeklyResetAt.map(formatResetTime) ?? "--")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("5h reset: \(snapshot.activeFiveHourResetAt.map(formatResetTime) ?? "--")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
            if let weeklyResetAt = snapshot.activeWeeklyResetAt {
                Text("Reset: \(formatResetTime(weeklyResetAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }

        if let mode = snapshot.mode, !mode.isEmpty {
            Text("Mode: \(mode.capitalized)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

    }

    private func metricRow(title: String, value: String, trailing: Bool) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private func formatResetTime(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().hour().minute())
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
