import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CodexPoolManager

// README screenshots must come from the real SwiftUI menu bar dashboard view.
// To regenerate from the repo root:
//
//   touch .generate-readme-menu-bar-screenshots
//   xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager \
//     -destination 'platform=macOS' \
//     '-only-testing:CodexPoolManagerTests/ReadmeMenuBarScreenshotGenerationTests/generatesLocalizedMenuBarScreenshotsWhenRequested()'
//   rm -f .generate-readme-menu-bar-screenshots
//
@MainActor
struct ReadmeMenuBarScreenshotGenerationTests {
    private static let generationFlag = "CODEX_POOL_GENERATE_README_SCREENSHOTS"
    private static let outputDirectoryOverride = "CODEX_POOL_README_SCREENSHOT_OUTPUT_DIR"
    private static let generationMarkerFileName = ".generate-readme-menu-bar-screenshots"

    @Test
    func generatesLocalizedMenuBarScreenshotsWhenRequested() throws {
        guard ProcessInfo.processInfo.environment[Self.generationFlag] == "1"
            || FileManager.default.fileExists(atPath: Self.generationMarkerURL.path)
        else {
            return
        }

        let outputDirectory = Self.outputDirectory()
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let previousLanguage = UserDefaults.standard.object(forKey: L10n.languageOverrideKey)
        let previousTimeZone = NSTimeZone.default
        defer {
            if let previousLanguage {
                UserDefaults.standard.set(previousLanguage, forKey: L10n.languageOverrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: L10n.languageOverrideKey)
            }
            NSTimeZone.default = previousTimeZone
        }

        let taipei = try #require(TimeZone(identifier: "Asia/Taipei"))
        NSTimeZone.default = taipei

        for locale in ScreenshotLocale.allCases {
            UserDefaults.standard.set(locale.languageCode, forKey: L10n.languageOverrideKey)
            let model = AppPoolRuntimeModel(
                store: ReadmeScreenshotStore(snapshot: Self.mockState.snapshot),
                initialState: Self.mockState,
                syncTimeoutNanoseconds: 1,
                menuBarClockIntervalNanoseconds: 0,
                menuBarNowProvider: { Self.referenceNow },
                widgetPublisher: { _ in },
                syncRunner: { state, viewState in
                    PoolDashboardUsageSyncFlowCoordinator.Output(
                        state: state,
                        viewState: viewState
                    )
                },
                officialSwitchRunner: { _ in .success("mock") },
                relaySwitchRunner: { _ in .success("mock") },
                defaults: Self.isolatedDefaults()
            )
            model.bootstrapIfNeeded()

            let view = MenuBarDashboardView(
                runtimeModel: model,
                openDashboard: {},
                switchAccount: { _ in }
            )
            .environment(\.locale, L10n.locale(for: locale.languageCode))
            .preferredColorScheme(.dark)

            let data = try Self.renderPNG(
                view,
                size: CGSize(width: 390, height: 500)
            )
            try data.write(to: outputDirectory.appendingPathComponent(locale.fileName))
        }
    }

    private static var mockState: AccountPoolState {
        AccountPoolState(snapshot: AccountPoolSnapshot(
            accounts: mockAccounts,
            groups: [AgentAccount.defaultGroupName],
            activities: [],
            mode: .manual,
            activeAccountID: activeAccountID,
            manualAccountID: activeAccountID,
            focusLockedAccountID: nil,
            minSwitchInterval: 300,
            lowUsageThresholdRatio: 0.15,
            lowUsageAlertsEnabled: true,
            minUsageRatioDeltaToSwitch: 0,
            lastSwitchAt: nil,
            lastUsageSyncAt: referenceNow.addingTimeInterval(-5 * 60),
            switchWithoutLaunching: false,
            autoSyncEnabled: false,
            autoSyncIntervalSeconds: 30
        ))
    }

    private static var mockAccounts: [AgentAccount] {
        [
            AgentAccount(
                id: activeAccountID,
                createdAt: date(year: 2026, month: 6, day: 20, hour: 10, minute: 0),
                name: "pro@example.com",
                groupName: "Default",
                usedUnits: 90,
                quota: 1000,
                apiToken: "mock-token-pro",
                email: "pro@example.com",
                chatGPTAccountID: "acct_demo_pro",
                usageWindowName: "weekly",
                usageWindowResetAt: date(year: 2026, month: 7, day: 7, hour: 9, minute: 55),
                primaryUsagePercent: 6,
                primaryUsageResetAt: date(year: 2026, month: 7, day: 1, hour: 12, minute: 9),
                isPaid: true,
                planType: "pro",
                rateLimitResetCreditsAvailableCount: 2,
                rateLimitResetCreditsEstimatedExpiresAt: date(year: 2026, month: 7, day: 30, hour: 20, minute: 3, second: 24),
                rateLimitResetCreditEstimatedExpiries: [
                    date(year: 2026, month: 7, day: 30, hour: 20, minute: 3, second: 24),
                    date(year: 2026, month: 8, day: 1, hour: 9, minute: 10, second: 11)
                ]
            ),
            AgentAccount(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                createdAt: date(year: 2026, month: 6, day: 21, hour: 10, minute: 0),
                name: "plus@example.com",
                groupName: "Default",
                usedUnits: 40,
                quota: 1000,
                apiToken: "mock-token-plus",
                email: "plus@example.com",
                chatGPTAccountID: "acct_demo_plus",
                usageWindowName: "weekly",
                usageWindowResetAt: date(year: 2026, month: 7, day: 8, hour: 11, minute: 56),
                primaryUsagePercent: 1,
                primaryUsageResetAt: date(year: 2026, month: 7, day: 2, hour: 16, minute: 7),
                isPaid: true,
                planType: "plus",
                rateLimitResetCreditsAvailableCount: 1,
                rateLimitResetCreditsEstimatedExpiresAt: date(year: 2026, month: 7, day: 31, hour: 11, minute: 56, second: 12),
                rateLimitResetCreditEstimatedExpiries: [
                    date(year: 2026, month: 7, day: 31, hour: 11, minute: 56, second: 12)
                ]
            ),
            AgentAccount(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                createdAt: date(year: 2026, month: 6, day: 22, hour: 10, minute: 0),
                name: "relay-key",
                groupName: "Default",
                usedUnits: 0,
                quota: 100,
                apiToken: "mock-relay-key",
                credentialType: .relayAPIKey,
                relayProviderID: "mock",
                relayProviderName: "Mock Relay",
                relayBaseURL: "https://relay.example.com",
                isPaid: false,
                usageSyncError: AgentAccount.relayUsageSyncUnavailableReason
            )
        ]
    }

    private static let activeAccountID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let referenceNow = date(year: 2026, month: 7, day: 3, hour: 0, minute: 0)

    private static func renderPNG<V: View>(
        _ rootView: V,
        size: CGSize
    ) throws -> Data {
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.appearance = NSAppearance(named: .darkAqua)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .windowBackgroundColor
        window.orderBack(nil)
        defer { window.orderOut(nil) }

        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let bounds = hostingView.bounds
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        hostingView.cacheDisplay(in: bounds, to: bitmap)

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    private static func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        ))!
    }

    private static func outputDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment[outputDirectoryOverride],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: override)
        }

        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/images")
    }

    private static var generationMarkerURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(generationMarkerFileName)
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "CodexPoolManager.ReadmeScreenshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: MenuBarAccountOrderSettings.activeAccountFirstKey)
        defaults.set(true, forKey: MenuBarAccountOrderSettings.paidAccountFirstKey)
        defaults.set(true, forKey: MenuBarAccountOrderSettings.apiKeyAccountLastKey)
        return defaults
    }
}

private enum ScreenshotLocale: CaseIterable {
    case english
    case traditionalChinese
    case simplifiedChinese
    case french
    case spanish
    case japanese
    case korean

    var languageCode: String {
        switch self {
        case .english:
            "en"
        case .traditionalChinese:
            "zh-Hant"
        case .simplifiedChinese:
            "zh-Hans"
        case .french:
            "fr"
        case .spanish:
            "es"
        case .japanese:
            "ja"
        case .korean:
            "ko"
        }
    }

    var fileName: String {
        switch self {
        case .english:
            "menu-bar.png"
        case .traditionalChinese:
            "menu-bar.zh-Hant.png"
        case .simplifiedChinese:
            "menu-bar.zh-Hans.png"
        case .french:
            "menu-bar.fr.png"
        case .spanish:
            "menu-bar.es.png"
        case .japanese:
            "menu-bar.ja.png"
        case .korean:
            "menu-bar.ko.png"
        }
    }
}

private final class ReadmeScreenshotStore: AccountPoolStoring {
    private var snapshot: AccountPoolSnapshot?

    init(snapshot: AccountPoolSnapshot?) {
        self.snapshot = snapshot
    }

    func load() -> AccountPoolSnapshot? {
        snapshot
    }

    func save(_ snapshot: AccountPoolSnapshot) {
        self.snapshot = snapshot
    }
}
