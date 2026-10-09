import CustomDump
import Foundation
import Testing
@testable import CodexPoolManager

enum SessionAnalyticsFixture {
    static let parentID = "11111111-1111-4111-8111-111111111111"
    static let childID = "22222222-2222-4222-8222-222222222222"
    static let otherID = "33333333-3333-4333-8333-333333333333"
    static let now = ISO8601DateFormatter().date(from: "2026-10-09T12:00:00Z")!

    static func line(_ type: String, payload: [String: Any], at timestamp: Date = now) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["type": type, "timestamp": ISO8601DateFormatter().string(from: timestamp), "payload": payload], options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func meta(_ id: String = parentID, parent: String? = nil, at timestamp: Date = now.addingTimeInterval(-3_600)) throws -> String {
        var payload: [String: Any] = ["id": id]
        if let parent { payload["forked_from_id"] = parent }
        return try line("session_meta", payload: payload, at: timestamp)
    }

    static func context(_ model: String) throws -> String {
        try line("turn_context", payload: ["model": model])
    }

    static func usage(_ input: Int, _ cache: Int = 0, _ output: Int = 0) -> [String: Int] {
        ["input_tokens": input, "cached_input_tokens": cache, "output_tokens": output, "reasoning_output_tokens": output / 2, "total_tokens": input + output]
    }

    static func event(total: [String: Int]? = nil, last: [String: Int]? = nil, source: String = "codex", at timestamp: Date = now) throws -> String {
        var info: [String: Any] = [:]
        if let total { info["total_token_usage"] = total }
        if let last { info["last_token_usage"] = last }
        return try line("event_msg", payload: ["type": "token_count", "info": info, "rate_limits": ["limit_id": source]], at: timestamp)
    }

    static func record(_ id: String = "fixture", model: String = "gpt-test", input: Int64 = 100, cached: Int64 = 20, output: Int64 = 30, at timestamp: Date = now) -> CodexSessionUsageRecord {
        CodexSessionUsageRecord(id: id, timestamp: timestamp, sessionID: parentID, model: model, tokens: CodexSessionTokens(input: input, cachedInput: cached, output: output))
    }

    static func report(_ records: [CodexSessionUsageRecord]) -> CodexSessionUsageReport {
        CodexSessionUsageReport(records: records, scannedFiles: 1)
    }

    static func calendar(_ zone: String = "Asia/Taipei") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }
}

struct CodexSessionAnalyticsTests {
    private let fixture = SessionAnalyticsFixture.self

    @Test
    func tokensNormalizeCacheAndDoNotAddReasoningTwice() throws {
        let tokens = CodexSessionTokens(input: 100, cachedInput: 120, output: 40)
        expectNoDifference(tokens, CodexSessionTokens(input: 100, cachedInput: 100, output: 40))
        expectNoDifference(tokens.freshInput, 0)
        expectNoDifference(tokens.total, 140)
        expectNoDifference(CodexSessionTokens(input: -5, cachedInput: 5, output: -1), CodexSessionTokens())
    }

    @Test
    func exactUsageWinsOverCumulativeAndDuplicateRateLimits() throws {
        let snapshot = fixture.usage(1_000, 800, 200)
        let last = fixture.usage(400, 300, 40)
        let text = try [fixture.meta(), fixture.context(" OPENAI/GPT-Test "), fixture.event(total: snapshot, last: last), fixture.event(total: snapshot, last: last, source: "review"), fixture.event(total: snapshot, last: last)].joined(separator: "\n")
        let report = CodexSessionLogParser.report(from: [CodexSessionLogParser.parse(text)])
        expectNoDifference(report.records.map(\.tokens), [CodexSessionTokens(input: 400, cachedInput: 300, output: 40)])
        expectNoDifference(report.records.map(\.model), ["gpt-test"])
        expectNoDifference(report.records.map(\.id), ["\(fixture.parentID):1"])
        expectNoDifference(report.isPartial, false)
    }

    @Test
    func cumulativeDeltasAreSessionScopedAcrossModelChanges() throws {
        let text = try [fixture.meta(), fixture.context("model-a"), fixture.event(total: fixture.usage(100, 30, 10)), fixture.context("model-b"), fixture.event(total: fixture.usage(160, 50, 20)), fixture.event(total: fixture.usage(160, 50, 20)), fixture.event(total: fixture.usage(90, 20, 5))].joined(separator: "\n")
        let events = CodexSessionLogParser.parse(text).events
        expectNoDifference(events.map(\.model), ["model-a", "model-b"])
        expectNoDifference(events.map(\.tokens), [CodexSessionTokens(input: 100, cachedInput: 30, output: 10), CodexSessionTokens(input: 60, cachedInput: 20, output: 10)])
    }

    @Test
    func oldSignatureMayRecurAfterCounterResetAndNewUsage() throws {
        let text = try [fixture.meta(), fixture.event(total: fixture.usage(100, 0, 10), last: fixture.usage(100, 0, 10)), fixture.event(total: fixture.usage(200, 0, 20), last: fixture.usage(100, 0, 10)), fixture.event(total: fixture.usage(100, 0, 10), last: fixture.usage(100, 0, 10))].joined(separator: "\n")
        expectNoDifference(CodexSessionLogParser.parse(text).events.count, 3)
    }

    @Test
    func acceptsCacheAliasAndIgnoresIncompleteOrUnrelatedLines() throws {
        let alias = ["input_tokens": 100, "cache_read_input_tokens": 70, "output_tokens": 20, "reasoning_output_tokens": 10]
        let text = try [fixture.meta(), fixture.line("response_item", payload: ["type": "message", "content": "fixture only"]), fixture.event(last: alias), fixture.line("event_msg", payload: ["type": "token_count", "info": NSNull()]), "{broken", fixture.event(total: fixture.usage(0))].joined(separator: "\n")
        expectNoDifference(CodexSessionLogParser.parse(text).events.map(\.tokens), [CodexSessionTokens(input: 100, cachedInput: 70, output: 20)])
    }

    @Test
    func archiveCopiesAndForkReplayAreNotCountedAgain() throws {
        let first = try fixture.event(total: fixture.usage(100, 50, 10), last: fixture.usage(100, 50, 10), at: fixture.now.addingTimeInterval(-1_800))
        let second = try fixture.event(total: fixture.usage(160, 70, 20), last: fixture.usage(60, 20, 10), at: fixture.now.addingTimeInterval(-1_200))
        let third = try fixture.event(total: fixture.usage(200, 80, 30), last: fixture.usage(40, 10, 10))
        let parent = try CodexSessionLogParser.parse([fixture.meta(), first, second].joined(separator: "\n"))
        let archived = try CodexSessionLogParser.parse([fixture.meta(), first].joined(separator: "\n"))
        let child = try CodexSessionLogParser.parse([fixture.meta(fixture.childID, parent: fixture.parentID, at: fixture.now.addingTimeInterval(-600)), first, second, third].joined(separator: "\n"))
        let report = CodexSessionLogParser.report(from: [archived, parent, child])
        expectNoDifference(report.records.map(\.id), ["\(fixture.childID):3", "\(fixture.parentID):2", "\(fixture.parentID):1"])
        expectNoDifference(CodexSessionAnalytics.summary(report.records, prices: [:]).tokens, CodexSessionTokens(input: 200, cachedInput: 80, output: 30))
        expectNoDifference(report.deferredFiles, 0)
    }

    @Test
    func copiedParentMetadataDoesNotBecomeForkStartTime() throws {
        let first = try fixture.event(total: fixture.usage(100, 50, 10), last: fixture.usage(100, 50, 10), at: fixture.now.addingTimeInterval(-1_800))
        let next = try fixture.event(total: fixture.usage(160, 70, 20), last: fixture.usage(60, 20, 10))
        let parent = try CodexSessionLogParser.parse([fixture.meta(), first].joined(separator: "\n"))
        let forkStartedAt = fixture.now.addingTimeInterval(-600)
        let child = try CodexSessionLogParser.parse([fixture.meta(), first, fixture.meta(fixture.childID, parent: fixture.parentID, at: forkStartedAt), next].joined(separator: "\n"), fileName: "rollout-\(fixture.childID).jsonl")
        expectNoDifference(child.startedAt, forkStartedAt)
        let report = CodexSessionLogParser.report(from: [parent, child])
        expectNoDifference(report.records.map(\.id), ["\(fixture.childID):2", "\(fixture.parentID):1"])
        expectNoDifference(CodexSessionAnalytics.summary(report.records, prices: [:]).tokens, CodexSessionTokens(input: 160, cachedInput: 70, output: 20))
    }

    @Test
    func forkWithMissingOrConflictingParentIsDeferred() throws {
        let event = try fixture.event(last: fixture.usage(100))
        let missing = try CodexSessionLogParser.parse([fixture.meta(fixture.childID, parent: fixture.parentID), event].joined(separator: "\n"))
        let selfParent = try CodexSessionLogParser.parse([fixture.meta(fixture.otherID, parent: fixture.otherID), event].joined(separator: "\n"))
        let conflictingMeta = try fixture.line("session_meta", payload: ["id": fixture.parentID, "forked_from_id": fixture.childID, "source": ["subagent": ["thread_spawn": ["parent_thread_id": fixture.otherID]]]])
        let conflicting = CodexSessionLogParser.parse(conflictingMeta + "\n" + event)
        let report = CodexSessionLogParser.report(from: [missing, selfParent, conflicting])
        expectNoDifference(report.records.count, 0)
        expectNoDifference(report.deferredFiles, 3)
        expectNoDifference(report.isPartial, true)
    }

    @Test
    func physicalThreadIDAndSubagentParentAreRecognized() throws {
        let meta = try fixture.line("session_meta", payload: ["id": fixture.parentID, "source": ["subagent": ["thread_spawn": ["parent_thread_id": fixture.parentID]]]])
        let parsed = CodexSessionLogParser.parse(meta, fileName: "rollout-2026-10-09-\(fixture.childID).jsonl")
        expectNoDifference(parsed.sessionID, fixture.childID)
        expectNoDifference(parsed.parentID, fixture.parentID)
    }

    @Test
    func cacheIsChargedOnceAndUnknownPricesAreNotZero() throws {
        let record = fixture.record(input: 1_000_000, cached: 750_000, output: 100_000)
        let price = CodexModelPrice(input: 2, cachedInput: 0.5, output: 8)
        let summary = CodexSessionAnalytics.summary([record], prices: ["gpt-test": price])
        expectNoDifference(summary.totalCost, 1.675)
        expectNoDifference(summary.cacheHitRate, 0.75)
        let unpriced = CodexSessionAnalytics.summary([record, fixture.record("unknown", model: "unknown")], prices: ["gpt-test": price])
        expectNoDifference(unpriced.totalCost, nil)
        expectNoDifference(unpriced.pricedCost, 1.675)
        expectNoDifference(unpriced.unpricedRequests, 1)
        expectNoDifference(CodexSessionAnalytics.summary([], prices: [:]).cacheHitRate, nil)
    }

    @Test(arguments: [-1.0, Double.infinity, Double.nan, 1_000_001])
    func invalidPricesRemainUnpriced(rate: Double) throws {
        let price = CodexModelPrice(input: rate, cachedInput: 0, output: 0)
        expectNoDifference(price.isValid, false)
        expectNoDifference(CodexSessionAnalytics.summary([fixture.record()], prices: ["gpt-test": price]).totalCost, nil)
    }

    @Test
    func customDateRangeIncludesEndDayAndExcludesFuture() throws {
        let calendar = fixture.calendar()
        let start = calendar.startOfDay(for: fixture.now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start)!
        let interval = CodexSessionUsageRange.custom.interval(now: fixture.now, calendar: calendar, customStart: fixture.now, customEnd: fixture.now.addingTimeInterval(-86_400))
        expectNoDifference(interval?.end, tomorrow)
        let records = [fixture.record("before", at: start.addingTimeInterval(-86_401)), fixture.record("in", at: start), fixture.record("future", at: tomorrow), fixture.record("other", model: "other", at: start)]
        expectNoDifference(CodexSessionAnalytics.filtered(records, interval: interval, model: "gpt-test", now: fixture.now).map(\.id), ["in"])
    }

    @Test
    func hourlyBucketsRespectLocalDatesAndModelSummaries() throws {
        let records = [fixture.record("one"), fixture.record("two", at: fixture.now.addingTimeInterval(-10)), fixture.record("three", model: "other", input: 10, cached: 0, output: 0, at: fixture.now.addingTimeInterval(-3_700))]
        let buckets = CodexSessionAnalytics.buckets(records, prices: [:], calendar: fixture.calendar(), hourly: true)
        expectNoDifference(buckets.map(\.summary.requestCount), [1, 1, 1])
        let daily = CodexSessionAnalytics.buckets(records, prices: [:], calendar: fixture.calendar(), hourly: false)
        expectNoDifference(daily.map(\.summary.requestCount), [3])
        let models = CodexSessionAnalytics.models(records, prices: [:])
        expectNoDifference(models.map(\.model), ["gpt-test", "other"])
        expectNoDifference(models.map(\.summary.tokens.total), [260, 10])
    }

    @Test
    func recentDayUses24HoursAcrossDaylightSaving() throws {
        let calendar = fixture.calendar("America/New_York")
        let now = ISO8601DateFormatter().date(from: "2026-11-01T20:00:00Z")!
        let interval = CodexSessionUsageRange.day.interval(now: now, calendar: calendar, customStart: now, customEnd: now)
        expectNoDifference(interval?.start, now.addingTimeInterval(-86_400))
    }
}

struct CodexSessionUsageStoreTests {
    @Test
    func rescansAppendAndArchiveMovesWithoutDuplicating() async throws {
        let fixture = SessionAnalyticsFixture.self
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-session-test-\(UUID().uuidString)", isDirectory: true)
        let sessions = directory.appendingPathComponent("sessions", isDirectory: true)
        let archived = directory.appendingPathComponent("archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = sessions.appendingPathComponent("rollout-\(fixture.parentID).jsonl")
        let first = try [fixture.meta(), fixture.context("gpt-test"), fixture.event(total: fixture.usage(100, 20, 10), last: fixture.usage(100, 20, 10))].joined(separator: "\n")
        try Data(first.utf8).write(to: url)
        let store = CodexSessionUsageStore()
        let original = try await store.scan(root: directory)
        expectNoDifference(original.records.count, 1)
        let repeated = try await store.scan(root: directory)
        expectNoDifference(repeated, original)
        let next = try fixture.event(total: fixture.usage(150, 30, 20), last: fixture.usage(50, 10, 10), at: fixture.now.addingTimeInterval(1))
        try Data((first + "\n" + next + "\n{incomplete").utf8).write(to: url)
        let appended = try await store.scan(root: directory)
        expectNoDifference(appended.records.count, 2)
        try FileManager.default.moveItem(at: url, to: archived.appendingPathComponent(url.lastPathComponent))
        let moved = try await store.scan(root: directory)
        expectNoDifference(moved, appended)
    }

    @Test
    func oversizedConversationBodiesDoNotPreventUsageParsing() async throws {
        let fixture = SessionAnalyticsFixture.self
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-session-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rollout-\(fixture.parentID).jsonl")
        let body = "{\"type\":\"response_item\",\"payload\":{\"content\":\"" + String(repeating: "x", count: 600_000) + "\"}}"
        let text = try [fixture.meta(), body, fixture.event(last: fixture.usage(100, 20, 10))].joined(separator: "\n")
        try Data(text.utf8).write(to: url)
        let report = try await CodexSessionUsageStore().scan(root: directory)
        expectNoDifference(report.records.map(\.tokens), [CodexSessionTokens(input: 100, cachedInput: 20, output: 10)])
        expectNoDifference(report.isPartial, false)
    }
}

@MainActor
struct SessionUsageAnalyticsModelTests {
    enum Failure: Error { case fixture }

    @Test
    func liveTestHostDoesNotReadPersonalSessions() async throws {
        let model = SessionUsageAnalyticsModel.live()
        await model.refreshButtonTapped()
        expectNoDifference(model.root, FileManager.default.temporaryDirectory.appendingPathComponent("CodexPoolManager.SessionAnalyticsTests", isDirectory: true))
        expectNoDifference(model.report, CodexSessionUsageReport())
        expectNoDifference(model.prices, [:])
    }

    @Test
    func successfulRefreshUsesInjectedClockAndClearsInvalidFilter() async throws {
        let fixture = SessionAnalyticsFixture.self
        let report = fixture.report([fixture.record()])
        let model = SessionUsageAnalyticsModel(root: URL(fileURLWithPath: "/fixture"), clock: { fixture.now }, load: { _ in report })
        model.selectedModel = "missing"
        await model.refreshButtonTapped()
        expectNoDifference(model.report, report)
        expectNoDifference(model.selectedModel, "")
        expectNoDifference(model.lastSyncedAt, fixture.now)
        expectNoDifference(model.isLoading, false)
        expectNoDifference(model.hasReadError, false)
    }

    @Test
    func failureAndCancellationKeepLastSuccessfulData() async throws {
        let fixture = SessionAnalyticsFixture.self
        let report = fixture.report([fixture.record()])
        let failed = SessionUsageAnalyticsModel(root: URL(fileURLWithPath: "/fixture"), report: report, clock: { fixture.now }, load: { _ in throw Failure.fixture })
        await failed.refreshButtonTapped()
        expectNoDifference(failed.report, report)
        expectNoDifference(failed.hasReadError, true)
        expectNoDifference(failed.isLoading, false)
        let cancelled = SessionUsageAnalyticsModel(root: URL(fileURLWithPath: "/fixture"), report: report, clock: { fixture.now }, load: { _ in throw CancellationError() })
        await cancelled.refreshButtonTapped()
        expectNoDifference(cancelled.report, report)
        expectNoDifference(cancelled.hasReadError, false)
        expectNoDifference(cancelled.lastSyncedAt, nil)
    }

    @Test
    func changedSourceRejectsLateOldSourceResults() async throws {
        let fixture = SessionAnalyticsFixture.self
        var pending: [URL: CheckedContinuation<CodexSessionUsageReport, Error>] = [:]
        let oldRoot = URL(fileURLWithPath: "/fixture/old")
        let newRoot = URL(fileURLWithPath: "/fixture/new")
        let model = SessionUsageAnalyticsModel(root: oldRoot, clock: { fixture.now }, load: { url in
            try await withCheckedThrowingContinuation { pending[url] = $0 }
        })
        let old = Task { await model.refreshButtonTapped() }
        while pending[oldRoot] == nil { await Task.yield() }
        let next = Task { await model.dataSourceChosen(newRoot) }
        while pending[newRoot] == nil { await Task.yield() }
        let updated = fixture.report([fixture.record("new")])
        pending[newRoot]?.resume(returning: updated)
        await next.value
        pending[oldRoot]?.resume(returning: fixture.report([fixture.record("old")]))
        await old.value
        expectNoDifference(model.root, newRoot)
        expectNoDifference(model.report, updated)
        expectNoDifference(model.isLoading, false)
    }

    @Test
    func invalidBookmarkDoesNotReplaceSourceOrData() async throws {
        let fixture = SessionAnalyticsFixture.self
        let original = URL(fileURLWithPath: "/fixture/old")
        let report = fixture.report([fixture.record()])
        let model = SessionUsageAnalyticsModel(root: original, report: report, clock: { fixture.now }, load: { _ in report }, saveRoot: { _ in throw Failure.fixture })
        await model.dataSourceChosen(URL(fileURLWithPath: "/fixture/new"))
        expectNoDifference(model.root, original)
        expectNoDifference(model.report, report)
        expectNoDifference(model.hasReadError, true)
    }

    @Test
    func pricesAreValidatedNormalizedPersistedAndRemoved() throws {
        let fixture = SessionAnalyticsFixture.self
        var saved: [[String: CodexModelPrice]] = []
        let model = SessionUsageAnalyticsModel(root: URL(fileURLWithPath: "/fixture"), clock: { fixture.now }, load: { _ in CodexSessionUsageReport() }, savePrices: { saved.append($0) })
        model.pricingButtonTapped(model: " OPENAI/GPT-Test ")
        let editor = try #require(model.priceEditor)
        editor.input = "garbage"
        editor.cachedInput = "0.5"
        editor.output = "8"
        model.savePricingButtonTapped()
        expectNoDifference(saved.count, 0)
        editor.input = "2"
        model.savePricingButtonTapped()
        expectNoDifference(model.prices, ["gpt-test": CodexModelPrice(input: 2, cachedInput: 0.5, output: 8)])
        expectNoDifference(saved.count, 1)
        expectNoDifference(model.priceEditor == nil, true)
        model.removePricingButtonTapped(model: "gpt-test")
        expectNoDifference(saved, [["gpt-test": CodexModelPrice(input: 2, cachedInput: 0.5, output: 8)], [:]])
    }
}
