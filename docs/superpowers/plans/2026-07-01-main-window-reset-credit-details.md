# Main Window Reset Credit Details Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add reset-credit count and per-credit estimated expiry details to the main dashboard account cards.

**Architecture:** Extract the existing menu bar reset-credit presentation into one shared formatter, then have both the menu bar presenter and `AccountUsagePanelView` consume that formatter. The main dashboard renders full details in normal layouts and a compact line in minimal layout, with the same estimate warning popover semantics.

**Tech Stack:** Swift 5, SwiftUI, Swift Testing, existing `L10n` localization and `AgentAccount` reset-credit fields.

---

### Task 1: Shared reset-credit presentation formatter

**Files:**
- Create: `CodexPoolManager/Support/ResetCreditPresentationFormatter.swift`
- Modify: `CodexPoolManager/MenuBar/MenuBarDashboardPresenter.swift`
- Test: `CodexPoolManagerTests/MenuBarDashboardPresenterTests.swift`

- [ ] **Step 1: Write failing shared formatter tests**

Add tests that call `ResetCreditPresentationFormatter.presentation(for:)` directly:

```swift
@Test
func resetCreditFormatterBuildsPerCreditDetailLines() throws {
    try withMenuBarLanguageAndTimeZoneOverride(
        "zh-Hant",
        timeZone: try #require(TimeZone(secondsFromGMT: 8 * 60 * 60))
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let firstExpiry = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 20, minute: 3, second: 24)))
        let secondExpiry = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 9, minute: 10, second: 11)))
        let account = makeAccount(
            rateLimitResetCreditsAvailableCount: 2,
            rateLimitResetCreditsEstimatedExpiresAt: firstExpiry,
            rateLimitResetCreditEstimatedExpiries: [firstExpiry, secondExpiry]
        )

        let presentation = try #require(ResetCreditPresentationFormatter.presentation(for: account))

        #expect(presentation.detailLines == [
            "可重置 2 次",
            "第 1 次期限：2026/7/30 20:03:24 GMT+8",
            "第 2 次期限：2026/8/1 09:10:11 GMT+8"
        ])
        #expect(presentation.noteText == "依前次成功同步時間加 30 天推估，實際期限可能不同。")
        #expect(presentation.accessibilityLabel == "可重置 2 次，推估 2026/7/30 20:03:24 GMT+8 到期")
    }
}

@Test
func resetCreditFormatterRepeatsLegacyExpiryWhenPerCreditListIsMissing() throws {
    try withMenuBarLanguageAndTimeZoneOverride(
        "zh-Hant",
        timeZone: try #require(TimeZone(secondsFromGMT: 8 * 60 * 60))
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let expiry = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 20, minute: 3, second: 24)))
        let account = makeAccount(
            rateLimitResetCreditsAvailableCount: 2,
            rateLimitResetCreditsEstimatedExpiresAt: expiry
        )

        let presentation = try #require(ResetCreditPresentationFormatter.presentation(for: account))

        #expect(presentation.detailLines == [
            "可重置 2 次",
            "第 1 次期限：2026/7/30 20:03:24 GMT+8",
            "第 2 次期限：2026/7/30 20:03:24 GMT+8"
        ])
    }
}

@Test
func resetCreditFormatterHidesUnsupportedOrIncompleteAccounts() {
    let expiry = Date(timeIntervalSince1970: 1_800_000_000)

    #expect(ResetCreditPresentationFormatter.presentation(for: makeAccount(
        rateLimitResetCreditsAvailableCount: 0,
        rateLimitResetCreditsEstimatedExpiresAt: expiry
    )) == nil)

    #expect(ResetCreditPresentationFormatter.presentation(for: makeAccount(
        rateLimitResetCreditsAvailableCount: 2,
        credentialType: .relayAPIKey
    )) == nil)

    #expect(ResetCreditPresentationFormatter.presentation(for: makeAccount(
        rateLimitResetCreditsAvailableCount: 2
    )) == nil)
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' '-only-testing:CodexPoolManagerTests/MenuBarDashboardPresenterTests' -quiet
```

Expected: fails because `ResetCreditPresentationFormatter` does not exist.

- [ ] **Step 3: Add shared formatter and update menu bar presenter**

Create `ResetCreditPresentationFormatter` with:

- `struct ResetCreditPresentation: Equatable`
- `detailLines: [String]`
- `detailText: String`
- `noteText: String?`
- `accessibilityLabel: String`
- `static func presentation(for account: AgentAccount) -> ResetCreditPresentation?`

Move the existing private reset-credit logic from `MenuBarDashboardPresenter` into the shared formatter. Change `MenuBarDashboardPresenter.makeAccountRow` to call the shared formatter.

- [ ] **Step 4: Run tests and verify GREEN**

Run the same command. Expected: all `MenuBarDashboardPresenterTests` pass.

- [ ] **Step 5: Commit**

```bash
git add CodexPoolManager/Support/ResetCreditPresentationFormatter.swift CodexPoolManager/MenuBar/MenuBarDashboardPresenter.swift CodexPoolManagerTests/MenuBarDashboardPresenterTests.swift
git commit -m "refactor: share reset credit presentation formatting"
```

### Task 2: Main dashboard account-card rendering

**Files:**
- Modify: `Features/PoolDashboard/Components/AccountUsagePanelView.swift`
- Test: `CodexPoolManagerTests/ViewSmokeCoverageTests.swift`

- [ ] **Step 1: Write failing source-smoke coverage**

Add a test that asserts the main account card renders reset-credit helpers:

```swift
@Test
func accountUsagePanelRendersResetCreditDetailsInAccountCards() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let repositoryRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
    let viewSourceURL = repositoryRoot.appendingPathComponent("Features/PoolDashboard/Components/AccountUsagePanelView.swift")
    let source = try String(contentsOf: viewSourceURL, encoding: .utf8)

    #expect(source.contains("accountResetCreditDetails(account, compact: false)"))
    #expect(source.contains("accountResetCreditDetails(account, compact: true)"))
    #expect(source.contains("ResetCreditPresentationFormatter.presentation(for: account)"))
    #expect(source.contains("isResetCreditNotePopoverPresented"))
    #expect(source.contains("exclamationmark.circle.fill"))
}
```

- [ ] **Step 2: Run test and verify RED**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' '-only-testing:CodexPoolManagerTests/ViewSmokeCoverageTests/accountUsagePanelRendersResetCreditDetailsInAccountCards()' -quiet
```

Expected: fails because the helper names are absent.

- [ ] **Step 3: Add SwiftUI reset-credit detail rendering**

Add `@State private var resetCreditNotePopoverAccountID: UUID?` to `AccountUsagePanelView`.

In `fullAccountCardContent`, render:

```swift
accountResetCreditDetails(account, compact: false)
```

after the weekly / 5-hour usage sections.

In `minimalAccountCardContent`, render:

```swift
accountResetCreditDetails(account, compact: true)
```

after the compact usage indicators.

Add helper views:

- `accountResetCreditDetails(_ account: AgentAccount, compact: Bool) -> some View`
- `resetCreditNoteButton(for account: AgentAccount, noteText: String) -> some View`

Use `ResetCreditPresentationFormatter.presentation(for: account)`. Full mode shows all `detailLines`; compact mode shows only `detailLines.first`. Both modes expose the note popover and help/accessibility text.

- [ ] **Step 4: Run source-smoke test and verify GREEN**

Run the same `ViewSmokeCoverageTests` command. Expected: pass.

- [ ] **Step 5: Run targeted presenter and view tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' '-only-testing:CodexPoolManagerTests/MenuBarDashboardPresenterTests' '-only-testing:CodexPoolManagerTests/ViewSmokeCoverageTests' -quiet
```

Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add Features/PoolDashboard/Components/AccountUsagePanelView.swift CodexPoolManagerTests/ViewSmokeCoverageTests.swift
git commit -m "feat: show reset credit details in main account cards"
```

### Task 3: Final validation and documentation handoff

**Files:**
- Modify only if needed: `README*.md`

- [ ] **Step 1: Run full relevant tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' -quiet
```

Expected: pass.

- [ ] **Step 2: Check git diff**

Run:

```bash
git status --short --branch
git log --oneline -5
```

Expected: branch is ahead only by the spec/plan and feature commits; no unstaged changes remain.

- [ ] **Step 3: Push**

Run:

```bash
git push origin main
```

Expected: `main -> main`.
