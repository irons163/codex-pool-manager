import Foundation
import Observation

@MainActor
@Observable
final class SessionUsageAnalyticsModel {
    enum DetailTab: String, CaseIterable, Identifiable {
        case requests, models, pricing
        var id: String { rawValue }
    }
    enum ChartMetric: String, CaseIterable, Identifiable {
        case tokens, requests, cost
        var id: String { rawValue }
    }

    var range: CodexSessionUsageRange = .week
    var selectedModel = ""
    var customStart: Date
    var customEnd: Date
    var detailTab: DetailTab = .requests
    var chartMetric: ChartMetric = .tokens
    var priceEditor: CodexModelPriceEditor?
    private(set) var report: CodexSessionUsageReport
    private(set) var prices: [String: CodexModelPrice]
    private(set) var root: URL
    private(set) var isLoading = false
    private(set) var hasReadError = false
    private(set) var lastSyncedAt: Date?
    private(set) var now: Date
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let load: (URL) async throws -> CodexSessionUsageReport
    @ObservationIgnored private let savePrices: ([String: CodexModelPrice]) -> Void
    @ObservationIgnored private let saveRoot: (URL) throws -> Void
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var loadingRoot: URL?

    init(
        root: URL,
        report: CodexSessionUsageReport = CodexSessionUsageReport(),
        prices: [String: CodexModelPrice] = [:],
        clock: @escaping () -> Date = { Date() },
        load: @escaping (URL) async throws -> CodexSessionUsageReport,
        savePrices: @escaping ([String: CodexModelPrice]) -> Void = { _ in },
        saveRoot: @escaping (URL) throws -> Void = { _ in }
    ) {
        self.root = root
        self.report = report
        self.prices = prices.filter { $0.value.isValid }
        self.clock = clock
        self.load = load
        self.savePrices = savePrices
        self.saveRoot = saveRoot
        let now = clock()
        self.now = now
        customStart = now
        customEnd = now
    }

    var availableModels: [String] { Set(report.records.map(\.model)).sorted() }

    var records: [CodexSessionUsageRecord] {
        CodexSessionAnalytics.filtered(
            report.records,
            interval: range.interval(now: now, calendar: .autoupdatingCurrent, customStart: customStart, customEnd: customEnd),
            model: selectedModel.isEmpty ? nil : selectedModel,
            now: now
        )
    }

    var summary: CodexSessionUsageSummary { CodexSessionAnalytics.summary(records, prices: prices) }
    var models: [CodexSessionModelSummary] { CodexSessionAnalytics.models(records, prices: prices) }
    var buckets: [CodexSessionUsageBucket] {
        CodexSessionAnalytics.buckets(records, prices: prices, calendar: .autoupdatingCurrent, hourly: range == .today || range == .day)
    }

    func task() async {
        await refreshButtonTapped()
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(60)) }
            catch { return }
            await refreshButtonTapped()
        }
    }

    func refreshButtonTapped() async {
        guard !isLoading || loadingRoot != root else { return }
        revision += 1
        let currentRevision = revision
        let currentRoot = root
        loadingRoot = currentRoot
        isLoading = true
        defer {
            if revision == currentRevision { isLoading = false; loadingRoot = nil }
        }
        do {
            let updated = try await load(currentRoot)
            try Task.checkCancellation()
            guard revision == currentRevision else { return }
            report = updated
            now = clock()
            lastSyncedAt = now
            hasReadError = false
            if !availableModels.contains(selectedModel) { selectedModel = "" }
        } catch is CancellationError { return }
        catch {
            if revision == currentRevision { hasReadError = true }
        }
    }

    func dataSourceChosen(_ url: URL) async {
        do { try saveRoot(url) }
        catch { hasReadError = true; return }
        root = url
        report = CodexSessionUsageReport()
        selectedModel = ""
        lastSyncedAt = nil
        await refreshButtonTapped()
    }

    func pricingButtonTapped(model: String) {
        priceEditor = CodexModelPriceEditor(model: model, price: prices[model])
    }

    func savePricingButtonTapped() {
        guard let editor = priceEditor, let price = editor.price else { return }
        let name = CodexSessionAnalytics.normalizedModel(editor.model)
        guard !name.isEmpty, name.count <= 120 else { return }
        prices[name] = price
        savePrices(prices)
        priceEditor = nil
    }

    func removePricingButtonTapped(model: String) {
        prices.removeValue(forKey: model)
        savePrices(prices)
    }

    static func live() -> SessionUsageAnalyticsModel {
        if AppRuntimeStorage.isRunningXCTest {
            return SessionUsageAnalyticsModel(
                root: FileManager.default.temporaryDirectory.appendingPathComponent("CodexPoolManager.SessionAnalyticsTests", isDirectory: true),
                load: { _ in CodexSessionUsageReport() }
            )
        }
        let defaults = AppRuntimeStorage.defaults
        let priceKey = "pool_dashboard.session_usage.prices"
        let sourceKey = "pool_dashboard.session_usage.root_bookmark"
        let store = CodexSessionUsageStore()
        let prices = defaults.data(forKey: priceKey).flatMap { try? JSONDecoder().decode([String: CodexModelPrice].self, from: $0) } ?? [:]
        var root: URL
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            root = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        }
        if let bookmark = defaults.data(forKey: sourceKey) {
            var stale = false
            if let restored = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) { root = restored }
        }
        return SessionUsageAnalyticsModel(
            root: root,
            prices: prices,
            load: { url in try await store.scan(root: url) },
            savePrices: { prices in
                if let data = try? JSONEncoder().encode(prices) { defaults.set(data, forKey: priceKey) }
            },
            saveRoot: { url in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                defaults.set(data, forKey: sourceKey)
            }
        )
    }
}

@MainActor
@Observable
final class CodexModelPriceEditor: Identifiable {
    var model: String
    var input: String
    var cachedInput: String
    var output: String

    init(model: String, price: CodexModelPrice?) {
        self.model = model
        input = price.map { String($0.input) } ?? ""
        cachedInput = price.map { String($0.cachedInput) } ?? ""
        output = price.map { String($0.output) } ?? ""
    }

    var price: CodexModelPrice? {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, model.count <= 120 else { return nil }
        func value(_ text: String) -> Double? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(trimmed.replacingOccurrences(of: L10n.locale().decimalSeparator ?? ".", with: "."))
        }
        guard let input = value(input), let cached = value(cachedInput), let output = value(output) else { return nil }
        let price = CodexModelPrice(input: input, cachedInput: cached, output: output)
        return price.isValid ? price : nil
    }
}
