# CodexPoolManager v1.0.20

Release date: 2026-10-05

This stable release brings together the menu bar, workspace, and OAuth refresh changes from v1.0.20-rc.1 through rc.7.

## Improvements

- Use a native 18-point, monochrome Codex menu bar icon that follows the system appearance. Keep the usage text and remove the elapsed-time suffix.
- Improve menu bar item visibility at startup and widen the menu bar dashboard's account list.
- Drag the original workspace title bar to adjust panel height from 10% to 90% of the window height. Remember the chosen height and show a vertical-resize cursor.
- Add a GitHub issue-reporting entry in Settings.

## Fixes

- Save refreshed OAuth credentials before fetching usage, so later errors or cancellation do not discard rotated tokens.
- Distinguish rejected credentials from network failures, rate limits, service errors, and missing refresh tokens.
- Prevent delayed refresh results from overwriting reimported credentials or restoring deleted accounts.

## Notes

- The OpenAI Reset Alert badge now reads “Removing soon”; the feature remains available in this release.
- Revoked credentials still require signing in again.
