# CodexPoolManager v1.0.21-rc.1

Release date: 2026-10-19

## Changes

- Keep personal and business workspaces sharing an email separate by workspace account ID, without borrowing credentials based on email alone.
- Verify newer local Codex credentials before updating the pool, and preserve verified credentials when a later sync fails or is cancelled.
- Stop usage sync and account switching when credentials belong to another workspace, with a clear sign-in prompt. Validate workspace identity during token refresh as well.
- Show a localized Business badge for Team, Business, and Enterprise accounts in account cards, the menu bar, and scheduling.
- Add local Codex session analytics with token usage, cache hit rate, estimated cost, trends, activity history, and model/request breakdowns.

## Prerelease Note

- This prerelease validates workspace separation and business account badges before stable v1.0.21. Credentials that have actually been revoked still require signing in again.
