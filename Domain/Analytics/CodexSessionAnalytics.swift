import Foundation

nonisolated struct CodexSessionTokens: Equatable, Hashable, Sendable {
    let input: Int64
    let cachedInput: Int64
    let output: Int64

    nonisolated init(input: Int64 = 0, cachedInput: Int64 = 0, output: Int64 = 0) {
        self.input = max(0, input)
        self.cachedInput = min(max(0, cachedInput), max(0, input))
        self.output = max(0, output)
    }

    nonisolated var freshInput: Int64 { input - cachedInput }
    nonisolated var total: Int64 { input + output }
    nonisolated var isEmpty: Bool { total == 0 }

    nonisolated func adding(_ other: Self) -> Self {
        Self(input: input + other.input, cachedInput: cachedInput + other.cachedInput, output: output + other.output)
    }

    nonisolated func delta(from previous: Self) -> Self {
        Self(input: max(0, input - previous.input), cachedInput: max(0, cachedInput - previous.cachedInput), output: max(0, output - previous.output))
    }

    nonisolated func highWater(with other: Self) -> Self {
        Self(input: max(input, other.input), cachedInput: max(cachedInput, other.cachedInput), output: max(output, other.output))
    }
}

nonisolated struct CodexSessionUsageRecord: Identifiable, Equatable, Sendable {
    let id: String
    let timestamp: Date
    let sessionID: String
    let model: String
    let tokens: CodexSessionTokens
}

nonisolated struct CodexSessionUsageReport: Equatable, Sendable {
    var records: [CodexSessionUsageRecord] = []
    var scannedFiles = 0
    var unavailableFiles = 0
    var deferredFiles = 0
    var isLimited = false

    nonisolated init(records: [CodexSessionUsageRecord] = [], scannedFiles: Int = 0, unavailableFiles: Int = 0, deferredFiles: Int = 0, isLimited: Bool = false) {
        self.records = records
        self.scannedFiles = scannedFiles
        self.unavailableFiles = unavailableFiles
        self.deferredFiles = deferredFiles
        self.isLimited = isLimited
    }

    nonisolated var isPartial: Bool { unavailableFiles > 0 || deferredFiles > 0 || isLimited }
}

nonisolated struct CodexModelPrice: Codable, Equatable, Sendable {
    var input: Double
    var cachedInput: Double
    var output: Double

    nonisolated var isValid: Bool {
        [input, cachedInput, output].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1_000_000 }
    }

    nonisolated func cost(for tokens: CodexSessionTokens) -> Double {
        (Double(tokens.freshInput) * input + Double(tokens.cachedInput) * cachedInput + Double(tokens.output) * output) / 1_000_000
    }
}

nonisolated enum CodexSessionUsageRange: String, CaseIterable, Identifiable, Sendable {
    case today, day, week, month, all, custom
    nonisolated var id: String { rawValue }

    nonisolated func interval(now: Date, calendar: Calendar, customStart: Date, customEnd: Date) -> DateInterval? {
        let start: Date
        switch self {
        case .today: start = calendar.startOfDay(for: now)
        case .day: start = now.addingTimeInterval(-86_400)
        case .week: start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .month: start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .all: return nil
        case .custom:
            let lower = calendar.startOfDay(for: min(customStart, customEnd))
            let upper = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(customStart, customEnd))) ?? now
            return DateInterval(start: lower, end: upper)
        }
        return DateInterval(start: min(start, now), end: now.addingTimeInterval(0.001))
    }
}

nonisolated struct CodexSessionUsageSummary: Equatable, Sendable {
    let requestCount: Int
    let tokens: CodexSessionTokens
    let pricedCost: Double
    let unpricedRequests: Int

    nonisolated var cacheHitRate: Double? { tokens.input > 0 ? Double(tokens.cachedInput) / Double(tokens.input) : nil }
    nonisolated var totalCost: Double? { unpricedRequests == 0 ? pricedCost : nil }
}

nonisolated struct CodexSessionUsageBucket: Identifiable, Sendable {
    let date: Date
    let summary: CodexSessionUsageSummary
    nonisolated var id: Date { date }
}

nonisolated struct CodexSessionModelSummary: Identifiable, Sendable {
    let model: String
    let summary: CodexSessionUsageSummary
    nonisolated var id: String { model }
}

nonisolated enum CodexSessionAnalytics {
    nonisolated static func normalizedModel(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/").last ?? "")
            .lowercased()
    }

    nonisolated static func filtered(
        _ records: [CodexSessionUsageRecord],
        interval: DateInterval?,
        model: String?,
        now: Date
    ) -> [CodexSessionUsageRecord] {
        records.filter { record in
            record.timestamp <= now
                && (model == nil || record.model == model)
                && (interval.map { record.timestamp >= $0.start && record.timestamp < $0.end } ?? true)
        }
    }

    nonisolated static func summary(_ records: [CodexSessionUsageRecord], prices: [String: CodexModelPrice]) -> CodexSessionUsageSummary {
        var tokens = CodexSessionTokens()
        var cost = 0.0
        var unpriced = 0
        for record in records {
            tokens = tokens.adding(record.tokens)
            if let price = prices[record.model], price.isValid {
                cost += price.cost(for: record.tokens)
            } else {
                unpriced += 1
            }
        }
        return CodexSessionUsageSummary(requestCount: records.count, tokens: tokens, pricedCost: cost, unpricedRequests: unpriced)
    }

    nonisolated static func buckets(
        _ records: [CodexSessionUsageRecord], prices: [String: CodexModelPrice], calendar: Calendar, hourly: Bool
    ) -> [CodexSessionUsageBucket] {
        Dictionary(grouping: records) { record in
            hourly ? (calendar.dateInterval(of: .hour, for: record.timestamp)?.start ?? record.timestamp) : calendar.startOfDay(for: record.timestamp)
        }
        .map { CodexSessionUsageBucket(date: $0.key, summary: summary($0.value, prices: prices)) }
        .sorted { $0.date < $1.date }
    }

    nonisolated static func models(_ records: [CodexSessionUsageRecord], prices: [String: CodexModelPrice]) -> [CodexSessionModelSummary] {
        Dictionary(grouping: records, by: \.model)
            .map { CodexSessionModelSummary(model: $0.key, summary: summary($0.value, prices: prices)) }
            .sorted { $0.summary.tokens.total == $1.summary.tokens.total ? $0.model < $1.model : $0.summary.tokens.total > $1.summary.tokens.total }
    }
}
