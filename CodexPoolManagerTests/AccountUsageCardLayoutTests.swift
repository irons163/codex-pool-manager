import AppKit
import SwiftUI
import Testing
@testable import CodexPoolManager

@Suite(.serialized)
struct AccountUsageCardLayoutTests {
    struct Scenario {
        let mode: String
        let width: CGFloat
        let columns: Int
    }

    private static let scenarios = [
        Scenario(mode: "single", width: 640, columns: 1),
        Scenario(mode: "double", width: 1_000, columns: 2),
        Scenario(mode: "triple", width: 1_440, columns: 3),
        Scenario(mode: "quad", width: 1_600, columns: 4),
        Scenario(mode: "minimal", width: 1_100, columns: 5),
        Scenario(mode: "quad", width: 520, columns: 2),
        Scenario(mode: "minimal", width: 360, columns: 1)
    ]

    @MainActor
    private final class Measurement {
        var cards: [UUID: CGRect] = [:]
        var contents: [UUID: CGRect] = [:]
    }

    @Test(arguments: scenarios, ["zh-Hant", "en", "fr"])
    @MainActor
    func cardsHaveEqualRowHeightsAndTopAlignedContent(scenario: Scenario, language: String) throws {
        let defaults = UserDefaults.standard
        let preferences: [String: Any] = [
            "pool_dashboard.account_usage.layout_mode": scenario.mode,
            "pool_dashboard.account_usage.sort_mode": "joinedAt",
            "pool_dashboard.account_usage.active_first": true,
            "pool_dashboard.account_usage.paid_first": false,
            "pool_dashboard.account_usage.api_key_last": true,
            L10n.languageOverrideKey: language
        ]
        let savedPreferences = Dictionary(uniqueKeysWithValues: preferences.keys.map { key in
            (key, defaults.object(forKey: key))
        })
        for (key, value) in preferences {
            defaults.set(value, forKey: key)
        }
        defer {
            for key in preferences.keys {
                if let value = savedPreferences[key] ?? nil {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        let accounts = Self.makeAccounts()
        let measurement = Measurement()
        let root = Self.gridView(accounts: accounts, width: scenario.width, language: language, measurement: measurement)

        let hostingView = NSHostingView(rootView: root)
        let size = CGSize(width: scenario.width + 32, height: 3_000)
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
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        #expect(measurement.cards.count >= accounts.count, "Every fixture card must be measured")
        #expect(measurement.contents.count >= accounts.count, "Every fixture's content must be measured")
        let rows = Self.rows(from: measurement.cards)
        #expect(rows.count >= (accounts.count + scenario.columns - 1) / scenario.columns)
        #expect(rows.count <= (accounts.count + scenario.columns - 1) / scenario.columns)
        for row in rows {
            let first = try #require(row.first)
            let firstFrame = try #require(measurement.cards[first])
            for id in row {
                let card = try #require(measurement.cards[id])
                let content = try #require(measurement.contents[id])
                #expect(abs(card.height - firstFrame.height) < 1, "Same-row cards must have equal heights: \(measurement.cards)")
                #expect(abs(content.minY - card.minY - 13) < 1, "Content must remain at the top, not centered")
                #expect(content.maxY <= card.maxY - 12, "Card height must not clip its natural content")
                #expect(card.minX >= -1 && card.maxX <= scenario.width + 1, "Cards must remain inside the available width")
            }
        }
        if scenario.columns > 1 {
            let rowHeights = rows.compactMap { row in row.first.flatMap { measurement.cards[$0]?.height } }
            #expect((rowHeights.max() ?? 0) - (rowHeights.min() ?? 0) > 1, "Short rows must not inherit another row's height")
        }

        if language == "zh-Hant", ["triple", "minimal"].contains(scenario.mode), scenario.width > 1_000 {
            let contentHeight = (measurement.cards.values.map(\.maxY).max() ?? 0) + 32
            let snapshotBounds = CGRect(x: 0, y: 0, width: size.width, height: contentHeight)
            let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: snapshotBounds))
            hostingView.cacheDisplay(in: snapshotBounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/codex-account-cards-\(scenario.mode).png"))
        }

        let originalTallestCard = measurement.cards.values.map(\.height).max() ?? 0
        let shorterAccounts = accounts.map { account in
            var updated = account
            updated.rateLimitResetCreditsAvailableCount = nil
            updated.rateLimitResetCreditEstimatedExpiries = []
            updated.rateLimitResetCreditsEstimatedExpiresAt = nil
            updated.rateLimitResetCreditExpirySource = nil
            updated.isUsageSyncExcluded = false
            updated.usageSyncError = nil
            return updated
        }
        hostingView.rootView = Self.gridView(accounts: shorterAccounts, width: scenario.width, language: language, measurement: measurement)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hostingView.layoutSubtreeIfNeeded()
        let updatedTallestCard = measurement.cards.values.map(\.height).max() ?? 0
        #expect(updatedTallestCard < originalTallestCard - 1, "Cards must shrink when optional details disappear")

        let narrowerWidth = min(scenario.width, 520)
        window.setContentSize(CGSize(width: narrowerWidth + 32, height: size.height))
        hostingView.rootView = Self.gridView(accounts: accounts, width: narrowerWidth, language: language, measurement: measurement)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hostingView.layoutSubtreeIfNeeded()
        for row in Self.rows(from: measurement.cards) {
            let first = try #require(row.first.flatMap { measurement.cards[$0] })
            for id in row {
                let card = try #require(measurement.cards[id])
                let content = try #require(measurement.contents[id])
                #expect(abs(card.height - first.height) < 1, "Same-row heights must remain equal after resizing")
                #expect(card.maxX <= narrowerWidth + 1, "Resizing must recalculate the available columns")
                #expect(content.maxY <= card.maxY - 12, "Resizing must not clip content")
            }
        }
    }

    @MainActor
    private static func gridView(accounts: [AgentAccount], width: CGFloat, language: String, measurement: Measurement) -> some View {
        AccountUsagePanelView.debugAccountGridView(accounts: accounts, availableWidth: width)
            .onPreferenceChange(AccountUsageCardFramePreferenceKey.self) { measurement.cards = $0 }
            .onPreferenceChange(AccountUsageCardContentFramePreferenceKey.self) { measurement.contents = $0 }
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .background(Color(red: 0.08, green: 0.10, blue: 0.14))
            .environment(\.locale, Locale(identifier: language))
            .environment(\.dynamicTypeSize, .medium)
            .preferredColorScheme(.dark)
    }

    private static func rows(from frames: [UUID: CGRect]) -> [[UUID]] {
        let sortedIDs = frames.keys.sorted { left, right in
            let lhs = frames[left] ?? .zero
            let rhs = frames[right] ?? .zero
            return abs(lhs.minY - rhs.minY) < 1 ? lhs.minX < rhs.minX : lhs.minY < rhs.minY
        }
        var rows: [[UUID]] = []
        for id in sortedIDs {
            if let lastRow = rows.last, let first = lastRow.first,
               abs((frames[first]?.minY ?? 0) - (frames[id]?.minY ?? 0)) < 1 {
                rows[rows.count - 1].append(id)
            } else {
                rows.append([id])
            }
        }
        return rows
    }

    private static func makeAccounts() -> [AgentAccount] {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        return (0..<9).map { index in
            let creditCount = index < 3 ? index : 0
            return AgentAccount(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                createdAt: date.addingTimeInterval(Double(-index)),
                name: "account\(index + 1)@example.com",
                usedUnits: index == 0 ? 47 : 16,
                quota: 100,
                email: "account\(index + 1)@example.com",
                chatGPTAccountID: "fixture-\(index)",
                usageWindowResetAt: date,
                primaryUsagePercent: index == 0 ? nil : 0,
                primaryUsageResetAt: index == 0 ? nil : date,
                secondaryUsagePercent: index == 0 ? nil : 16,
                isPaid: true,
                rateLimitResetCreditsAvailableCount: creditCount,
                rateLimitResetCreditEstimatedExpiries: (0..<creditCount).map { date.addingTimeInterval(Double($0) * 86_400) },
                rateLimitResetCreditExpirySource: creditCount > 0 ? .api : nil,
                isUsageSyncExcluded: index == 6,
                usageSyncError: index == 6 ? L10n.text("sync.excluded.default_message") : nil
            )
        }
    }
}
