import AppKit
import CustomDump
import SwiftUI
import Testing
@testable import CodexPoolManager

@Suite(.serialized)
@MainActor
struct SessionUsageAnalyticsLayoutTests {
    struct Scenario {
        let name: String
        let width: CGFloat
        let tab: SessionUsageAnalyticsModel.DetailTab
        let empty: Bool
        let partial: Bool
        let light: Bool
    }

    private static let scenarios = [
        Scenario(name: "wide", width: 1_180, tab: .requests, empty: false, partial: false, light: false),
        Scenario(name: "narrow", width: 520, tab: .requests, empty: false, partial: false, light: false),
        Scenario(name: "models", width: 900, tab: .models, empty: false, partial: false, light: false),
        Scenario(name: "pricing", width: 520, tab: .pricing, empty: false, partial: true, light: false),
        Scenario(name: "empty", width: 520, tab: .requests, empty: true, partial: false, light: false),
        Scenario(name: "light", width: 1_180, tab: .requests, empty: false, partial: false, light: true)
    ]

    @Test(arguments: scenarios, ["zh-Hant", "en", "fr"])
    func rendersWithoutScanningPersonalData(scenario: Scenario, language: String) throws {
        let defaults = UserDefaults.standard
        let savedLanguage = defaults.object(forKey: L10n.languageOverrideKey)
        let wasLight = PoolDashboardTheme.isLightPalette
        defaults.set(language, forKey: L10n.languageOverrideKey)
        PoolDashboardTheme.forcePalette(isLight: scenario.light)
        defer {
            if let savedLanguage { defaults.set(savedLanguage, forKey: L10n.languageOverrideKey) }
            else { defaults.removeObject(forKey: L10n.languageOverrideKey) }
            PoolDashboardTheme.forcePalette(isLight: wasLight)
        }
        let fixture = SessionAnalyticsFixture.self
        var records: [CodexSessionUsageRecord] = []
        for index in 0..<35 {
            let name = index.isMultiple(of: 3) ? "gpt-test-mini" : "gpt-test"
            let input = Int64(20_000 + index * 2_000)
            let cached = Int64(10_000 + index * 600)
            let output = Int64(1_000 + index * 200)
            let timestamp = fixture.now.addingTimeInterval(-Double(index) * 16_800)
            records.append(fixture.record("preview-\(index)", model: name, input: input, cached: cached, output: output, at: timestamp))
        }
        var loadCount = 0
        let model = SessionUsageAnalyticsModel(
            root: URL(fileURLWithPath: "/fixture/codex"),
            report: CodexSessionUsageReport(records: scenario.empty ? [] : records, scannedFiles: scenario.empty ? 0 : 4, deferredFiles: scenario.partial ? 1 : 0),
            prices: ["gpt-test": CodexModelPrice(input: 2, cachedInput: 0.5, output: 8), "gpt-test-mini": CodexModelPrice(input: 0.4, cachedInput: 0.1, output: 1.6)],
            clock: { fixture.now },
            load: { _ in loadCount += 1; return CodexSessionUsageReport() }
        )
        model.detailTab = scenario.tab
        if scenario.partial { model.range = .custom; model.customStart = fixture.now.addingTimeInterval(-7 * 86_400) }
        let size = CGSize(width: scenario.width, height: 1_150)
        let hostingView = NSHostingView(rootView:
            ScrollView {
                SessionUsageAnalyticsPanelView(model: model, scansAutomatically: false)
                    .padding(24)
            }
            .foregroundStyle(PoolDashboardTheme.textPrimary)
            .background(PoolDashboardTheme.backgroundGradient)
            .environment(\.colorScheme, scenario.light ? .light : .dark)
            .environment(\.locale, L10n.locale(for: language))
        )
        hostingView.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hostingView
        window.appearance = NSAppearance(named: scenario.light ? .aqua : .darkAqua)
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        expectNoDifference(loadCount, 0)
        expectNoDifference(hostingView.frame.width, scenario.width)
        if language == "zh-Hant" || (language == "fr" && scenario.name == "narrow") {
            let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
            hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/codex-session-analytics-\(scenario.name)-\(language).png"))
        }
    }
}
