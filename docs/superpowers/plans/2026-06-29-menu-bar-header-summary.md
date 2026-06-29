# Menu Bar Header Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the menu bar dashboard's four large summary cards and move the same status information into the header subtitle.

**Architecture:** Keep the existing `MenuBarDashboardPresenter` values as the source of truth. Add a lightweight header-summary string on the snapshot, render it in `MenuBarDashboardView`, and remove the `summaryGrid`/`SummaryTile` body section.

**Tech Stack:** Swift, SwiftUI, Swift Testing, macOS menu bar `MenuBarExtra` popover.

---

### Task 1: Add compact header summary to the presenter

**Files:**
- Modify: `CodexPoolManager/MenuBar/MenuBarDashboardPresenter.swift`
- Test: `CodexPoolManagerTests/MenuBarDashboardPresenterTests.swift`

- [ ] **Step 1: Write the failing test**

Add this assertion to `presenterBuildsPaidActiveAccountSummary()` after the existing mode assertion:

```swift
#expect(snapshot.headerSummaryText == "\(L10n.text("menu_bar.header.subtitle")) · \(L10n.text("menu_bar.summary.accounts")) 2 · \(L10n.text("menu_bar.summary.available")) 2 · \(L10n.text("menu_bar.summary.usage")) 50% · \(L10n.text("mode.manual"))")
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' -only-testing:CodexPoolManagerTests/MenuBarDashboardPresenterTests
```

Expected: FAIL because `MenuBarDashboardSnapshot` has no `headerSummaryText` property.

- [ ] **Step 3: Add the presenter property and value**

In `MenuBarDashboardSnapshot`, add:

```swift
let headerSummaryText: String
```

In `makeSnapshot`, compute `totalAccountsText`, `availableAccountsText`, `usageText`, and `modeText` once, then pass:

```swift
headerSummaryText: headerSummaryText(
    totalAccountsText: totalAccountsText,
    availableAccountsText: availableAccountsText,
    usageText: usageText,
    modeText: modeText
),
```

Add this helper:

```swift
private static func headerSummaryText(
    totalAccountsText: String,
    availableAccountsText: String,
    usageText: String,
    modeText: String
) -> String {
    [
        L10n.text("menu_bar.header.subtitle"),
        "\(L10n.text("menu_bar.summary.accounts")) \(totalAccountsText)",
        "\(L10n.text("menu_bar.summary.available")) \(availableAccountsText)",
        "\(L10n.text("menu_bar.summary.usage")) \(usageText)",
        modeText
    ].joined(separator: " · ")
}
```

- [ ] **Step 4: Run the presenter test to verify it passes**

Run the same command as Step 2.

Expected: PASS.

### Task 2: Render header summary and remove summary tiles

**Files:**
- Modify: `CodexPoolManager/MenuBar/MenuBarDashboardView.swift`
- Test: `CodexPoolManagerTests/ViewSmokeCoverageTests.swift`

- [ ] **Step 1: Write the failing view smoke assertion**

In `richMenuBarDashboardViewRendersWithRuntimeModel()`, after rendering, add:

```swift
#expect(runtimeModel.menuBarSnapshot.headerSummaryText.contains(L10n.text("menu_bar.summary.accounts")))
```

This confirms the view has access to the compact summary value before rendering changes.

- [ ] **Step 2: Run the smoke test**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' -only-testing:CodexPoolManagerTests/ViewSmokeCoverageTests/richMenuBarDashboardViewRendersWithRuntimeModel
```

Expected after Task 1: PASS. This is a guard test rather than the red test because SwiftUI private subviews are not introspected in this test suite.

- [ ] **Step 3: Update `MenuBarDashboardView`**

Replace the static subtitle:

```swift
Text(L10n.text("menu_bar.header.subtitle"))
```

with:

```swift
Text(snapshot.headerSummaryText)
```

Use compact text behavior:

```swift
.lineLimit(1)
.minimumScaleFactor(0.72)
```

Remove `summaryGrid` from the body:

```swift
-                    summaryGrid
                     activeAccountSection
```

Delete the `summaryGrid` computed property and delete the private `SummaryTile` view because nothing should use it anymore.

- [ ] **Step 4: Run the smoke test**

Run the same command as Step 2.

Expected: PASS.

### Task 3: Verify and commit

**Files:**
- Verify: `CodexPoolManager/MenuBar/MenuBarDashboardPresenter.swift`
- Verify: `CodexPoolManager/MenuBar/MenuBarDashboardView.swift`
- Verify: `CodexPoolManagerTests/MenuBarDashboardPresenterTests.swift`
- Verify: `CodexPoolManagerTests/ViewSmokeCoverageTests.swift`
- Verify: `docs/superpowers/specs/2026-06-29-menu-bar-header-summary-design.md`
- Verify: `docs/superpowers/plans/2026-06-29-menu-bar-header-summary.md`

- [ ] **Step 1: Run targeted tests**

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' -only-testing:CodexPoolManagerTests/MenuBarDashboardPresenterTests -only-testing:CodexPoolManagerTests/ViewSmokeCoverageTests/richMenuBarDashboardViewRendersWithRuntimeModel
```

Expected: PASS.

- [ ] **Step 2: Run localization lint**

```bash
for file in CodexPoolManager/*.lproj/Localizable.strings; do plutil -lint "$file"; done
```

Expected: every file reports `OK`.

- [ ] **Step 3: Commit**

```bash
git add CodexPoolManager/MenuBar/MenuBarDashboardPresenter.swift CodexPoolManager/MenuBar/MenuBarDashboardView.swift CodexPoolManagerTests/MenuBarDashboardPresenterTests.swift CodexPoolManagerTests/ViewSmokeCoverageTests.swift docs/superpowers/plans/2026-06-29-menu-bar-header-summary.md
git commit -m "fix(menu-bar): compact dashboard summary into header"
```
