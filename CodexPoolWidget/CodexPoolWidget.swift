import WidgetKit
import SwiftUI

struct WidgetBridgeSnapshot: Codable {
    let updatedAt: Date
    let status: String
    let source: String
}

private enum WidgetBridgeSnapshotStore {
    static let appGroupIdentifier = "group.com.irons.codexpoolbridge"
    static let snapshotFileName = "snapshot.json"

    static func load() -> WidgetBridgeSnapshot? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }

        let url = containerURL.appendingPathComponent(snapshotFileName)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetBridgeSnapshot.self, from: data)
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
                source: "CodexPoolManager"
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
            Text("Codex Pool")
                .font(.headline)

            if let snapshot = entry.snapshot {
                Text(snapshot.status)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

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

            Text(entry.date, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
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
