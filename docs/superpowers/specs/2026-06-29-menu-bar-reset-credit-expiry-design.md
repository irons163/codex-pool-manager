# Menu Bar Reset Credit Expiry Estimate Design

Date: 2026-06-29

## Goal

Remove the duplicated current-account section from the menu bar dashboard and show each eligible account's banked Codex rate-limit reset count with a compact, explicitly estimated expiry date.

## User-Approved Direction

The menu bar account list remains the single account section. The separate `目前帳號` card is removed because the selected account is already highlighted in the list.

For an account with banked resets, the first line adds a compact badge similar to:

`↻ 2 · 約 7/29 到期`

The estimate may be imprecise. The user explicitly prefers a useful estimated date over a generic `入帳後 30 天` message.

## Data Source and Constraint

The existing usage request already calls `GET /backend-api/wham/usage`. Extend its decoder to read:

`rate_limit_reset_credits.available_count`

The response exposes the available count but does not expose individual grant timestamps or expiry timestamps. OpenAI's published rule says a banked reset is normally usable for 30 days after it is granted. Therefore the app must label the displayed date as an estimate and must not present it as an exact server-provided expiry.

References:

- [OpenAI Codex backend usage type](https://github.com/openai/codex/blob/main/codex-rs/backend-client/src/types.rs)
- [Using Codex with your ChatGPT plan](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan)

## Expiry Estimation

Store the reset count and one estimated earliest expiry date on each `AgentAccount`.

When a successful usage sync first observes a positive reset count for an account:

1. Read the pool's successful sync timestamp from before the current sync.
2. Use that previous successful sync timestamp as the estimated observation boundary.
3. If no previous successful sync exists, use the current sync time.
4. Add 30 days to produce the estimated expiry.

Once a positive count has an estimate, later positive counts retain the existing date. This intentionally keeps the first-observed estimate even if the count changes, because the API cannot identify individual reset grants and the earliest estimate is the safer compact summary.

When a successful response reports zero resets, clear the estimate. If a future sync later reports a positive count again, create a new estimate using the same rule.

When the field is absent from a successful response, treat it as unavailable and hide reset-credit metadata. A failed usage request does not overwrite the last successful values.

Clamp negative counts to zero. If a stored previous-sync timestamp is later than the current sync time, use the current sync time instead.

## Model and Data Flow

`OpenAICodexUsageClient` decodes the reset count into `CodexUsage`. `CodexUsageSyncService` captures the pool's `lastUsageSyncAt` before starting the account loop and passes that timestamp with the decoded count into account-state mutation.

`AgentAccount` persists:

- the latest available reset count;
- the estimated expiry date.

Both fields decode with backward-compatible defaults so existing saved pools continue to load. Token-redacted copies, account duplication, and synchronized-state merges preserve the new fields.

`MenuBarDashboardPresenter` formats the count and estimated local date for `MenuBarAccountRow`. The SwiftUI view only renders the badge when the count is greater than zero and an estimated expiry exists.

## Layout and Interaction

The menu bar body changes from:

1. Current-account section.
2. Warning presentation.
3. Account section.

to:

1. Warning presentation.
2. Account section.

The active account remains identifiable through the existing blue highlight, leading status dot, and checkmark.

The reset badge sits on the account's first line after the plan badge. It uses compact typography and does not add a third row. Selecting the badge opens a small popover that explains:

- the currently reported available count;
- the estimated expiry date;
- that the date is calculated from the previous successful sync plus 30 days and may differ from OpenAI's actual expiry.

The existing weekly and 5-hour usage percentages and reset timestamps remain unchanged on the second line.

## Localization

Add localized strings for:

- the compact count and estimated-expiry badge;
- the detail-popover title;
- the estimate explanation;
- the reset badge's accessibility label.

All supported `.lproj` folders receive matching keys. Accessibility labels expose the reset count and full estimated date without relying on the arrow icon.

## Error and Compatibility Behavior

- API key relay accounts do not show the reset badge.
- Accounts with zero or unavailable reset counts do not show an empty placeholder.
- Failed syncs preserve the last successful count and estimate.
- Existing account archives without the new fields decode normally.
- The menu bar group filter, ordering preferences, account switching, warnings, and exact weekly/5-hour reset times remain unchanged.

## Testing

Use test-driven development for implementation.

Automated tests cover:

- decoding `rate_limit_reset_credits.available_count` from usage JSON;
- clamping a negative count to zero;
- estimating first-observed expiry from the previous successful sync plus 30 days;
- falling back to the current sync time when no prior successful sync exists;
- retaining the estimate while the count remains positive;
- clearing the estimate when the count becomes zero;
- backward-compatible `AgentAccount` decoding;
- presenter formatting of the compact reset badge and estimated date;
- absence of the duplicated current-account section in the menu bar view;
- continued two-line account-row layout and existing group/order behavior.

Manual QA should confirm the account row remains readable at the current popover width, the badge opens its explanation, and Traditional Chinese dates do not clip.

## Non-Goals

- Do not consume a banked reset from this app.
- Do not claim that the estimated expiry came from OpenAI's API.
- Do not infer or store individual reset-grant records.
- Do not redesign weekly or 5-hour usage presentation.
- Do not change the main-window account layout.
