# Main Window Reset Credit Details Design

Date: 2026-07-01

## Goal

Show Codex rate-limit reset-credit availability and estimated per-credit expiry details in the main dashboard account cards, matching the information already shown in the menu bar dashboard.

## User-Approved Direction

Use the full-detail presentation in the main window:

```text
可重置 2 次
第 1 次期限：2026/7/30 20:03:24 GMT+8
第 2 次期限：2026/7/30 20:03:24 GMT+8
```

The main window should keep the same warning/explanation pattern as the menu bar: an exclamation icon opens the note that the expiry is estimated from the previous successful sync time plus 30 days and may differ from the actual OpenAI expiry.

## Existing Data Source

No new sync endpoint or storage field is needed. `AgentAccount` already stores:

- `rateLimitResetCreditsAvailableCount`
- `rateLimitResetCreditsEstimatedExpiresAt`
- `rateLimitResetCreditEstimatedExpiries`

The menu bar already formats these through `MenuBarDashboardPresenter`. The main window should reuse the same presentation semantics so the two surfaces do not drift.

## Main Dashboard Placement

Update `AccountUsagePanelView` account cards:

- Full layout: show reset-credit details below the existing weekly / 5-hour usage sections.
- Minimal layout: show a compact `可重置 N 次` line with tooltip/popover details, so the minimal card does not grow as aggressively as the full card.
- Relay API Key accounts do not show reset-credit details because they do not support Codex subscription usage sync.
- Accounts with zero or unavailable reset credits do not show a placeholder.

The new content should not move the account name, group label, usage meters, or switch buttons.

## Presentation Rules

Use the same rules as the menu bar:

1. Display only when the account supports Codex usage sync, the count is positive, and at least one estimated expiry exists.
2. Show one expiry line per available credit.
3. If fewer stored per-credit expiry dates exist than the count, repeat the last known expiry, matching the menu bar fallback.
4. Format exact local time as `yyyy/M/d HH:mm:ss GMT±H[:MM]`.
5. Mark the explanation as an estimate, not as an API-provided exact expiry.

## Localization

Prefer reusing existing menu-bar localization keys when the wording is identical:

- `menu_bar.reset_credit.detail_format`
- `menu_bar.reset_credit.per_credit_expiry_format`
- `menu_bar.reset_credit.accessibility_format`

If the main dashboard needs a more specific wording or tooltip, add account-specific localization keys to all supported `.lproj` folders.

## Testing

Add focused coverage for the new main-window presentation without expanding the whole UI test surface:

- presenter/formatter coverage for full detail lines when count and per-credit expiries exist;
- fallback behavior when only the legacy single expiry exists;
- hidden state for relay/API-key accounts, zero count, or missing expiry;
- smoke/source coverage that `AccountUsagePanelView` renders reset-credit detail helpers in full and minimal layouts.

Run targeted tests for account model reset-credit behavior, menu bar presenter behavior if shared helpers move, and view smoke coverage.

## Non-Goals

- Do not change reset-credit estimation rules.
- Do not add new API calls.
- Do not redesign the main dashboard account card layout.
- Do not change menu bar UI behavior.
- Do not create real per-grant expiry records; the stored dates remain estimates.
