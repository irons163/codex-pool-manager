import AppKit
import SwiftUI
import Testing
@testable import CodexPoolManager

@Suite(.serialized)
struct AccountUsageHeaderLayoutTests {
    @MainActor
    private final class Measurement {
        var titleSize: CGSize = .zero
    }

    @Test(arguments: [520.0, 760.0, 940.0, 1_120.0, 1_400.0], ["zh-Hant", "zh-Hans", "en", "ja", "ko", "fr", "es"])
    @MainActor
    func layoutTitleStaysOnOneLine(width: Double, language: String) throws {
        let defaults = UserDefaults.standard
        let oldLanguage = defaults.object(forKey: L10n.languageOverrideKey)
        defaults.set(language, forKey: L10n.languageOverrideKey)
        defer {
            if let oldLanguage {
                defaults.set(oldLanguage, forKey: L10n.languageOverrideKey)
            } else {
                defaults.removeObject(forKey: L10n.languageOverrideKey)
            }
        }

        let measurement = Measurement()
        let root = AccountUsagePanelView.debugHeaderControlsView(availableWidth: 1_400)
            .onPreferenceChange(AccountUsageLayoutTitleSizePreferenceKey.self) { size in
                measurement.titleSize = size
            }
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .background(Color(red: 0.08, green: 0.10, blue: 0.14))
            .environment(\.locale, Locale(identifier: language))
            .environment(\.dynamicTypeSize, .medium)
            .preferredColorScheme(.dark)

        let hostingView = NSHostingView(rootView: root)
        let size = CGSize(width: width + 32, height: 200)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.appearance = NSAppearance(named: .darkAqua)
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let titleSize = measurement.titleSize
        #expect(titleSize.width > titleSize.height + 1, "The layout title must not become vertical: \(titleSize)")
        #expect(titleSize.height > 0 && titleSize.height < 25, "The layout title must occupy one line: \(titleSize)")

        if language == "zh-Hant", [760.0, 1_120.0, 1_400.0].contains(width) {
            let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
            hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/codex-account-header-\(Int(width)).png"))
        }
    }
}
