import WidgetKit
import SwiftUI

struct CodexPoolWidgetEntry: TimelineEntry {
    let date: Date
}

struct CodexPoolWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexPoolWidgetEntry {
        CodexPoolWidgetEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexPoolWidgetEntry) -> Void) {
        completion(CodexPoolWidgetEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexPoolWidgetEntry>) -> Void) {
        let currentDate = Date()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate) ?? currentDate.addingTimeInterval(1800)

        let entry = CodexPoolWidgetEntry(date: currentDate)
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

            Text(entry.date, style: .time)
                .font(.title3.weight(.semibold))
                .monospacedDigit()

            Text("Widget is active")
                .font(.caption)
                .foregroundStyle(.secondary)
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
