# Menu Bar Header Summary Design

Date: 2026-06-29

## Goal

Make the menu bar dashboard feel less crowded by removing the four large summary tiles and moving their information into the header subtitle.

## User-Approved Direction

Use option 3 from the compact summary discussion: put the status summary in the header area.

The subtitle should become a single compact line similar to:

`Menu bar dashboard · Accounts 9 · Available 2 · Usage 88% · Smart switching`

In Traditional Chinese this should read similarly to:

`選單列儀表板 · 帳號 9 · 可用 2 · 用量 88% · 智能切換`

## Scope

- Remove the four large summary tiles from the popover body.
- Keep the status information visible in the header subtitle.
- Keep the existing last-updated row below the action buttons.
- Keep account rows, active-account card, warning rows, and dashboard actions unchanged.
- Keep all user-facing strings localized through existing `L10n` keys.

## Non-Goals

- Do not redesign the account rows.
- Do not change the menu bar popover width.
- Do not change sync, switching, or runtime model behavior.
- Do not add new account metrics.

## Layout

The top of the popover should flow as:

1. App icon, app title, compact subtitle summary.
2. Sync and Open Dashboard buttons.
3. Last sync status.
4. Active account section.
5. Warning rows.
6. Account list.

This removes the separate summary-grid section entirely and gives the first visible account card more vertical space.

## Data Flow

`MenuBarDashboardPresenter` already exposes:

- `totalAccountsText`
- `availableAccountsText`
- `usageText`
- `modeText`

The view can compose the header subtitle from those values and the existing localized labels. No model or persistence changes are required.

## Error Handling

There is no new error path. If the snapshot has zero accounts, the existing empty state remains and the compact summary does not need to render separately.

## Testing

Add or update tests to verify:

- The compact header summary contains account count, available count, usage, and mode.
- The old `SummaryTile` grid is no longer present in the menu bar body.
- Existing presenter values remain unchanged.

Manual QA should confirm that the menu bar popover no longer shows the four large status cards and that the header subtitle fits in Traditional Chinese at the current width.
