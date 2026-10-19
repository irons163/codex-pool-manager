# CodexPoolManager v1.0.21

Release date: 2026-10-19

## Improvements

- Add local Codex usage analytics with token totals, cache hit rate, estimated costs, trends, activity history, and model/request breakdowns.
- Show Business badges for Team, Business, and Enterprise accounts across account cards, the menu bar, and scheduling.
- Keep “Report an issue” at the bottom of the sidebar, with GitHub and in-app email options. Reports go to `feedback@codexpool.zero2codex.dev` without opening a mail application.
- Make the reply address optional and attach app/system versions only when selected. Unchanged retries do not send duplicate reports.

## Fixes

- Separate personal and business workspaces sharing an email, and distinguish members of the same workspace during login recovery, import, refresh, usage sync, and switching.
- Highlight only the selected account as current and reject credentials belonging to another workspace or member.
- Read linked session directories and complete large session logs while skipping conversation bodies, restoring missing usage events and avoiding false incomplete-statistics warnings.

## Updating

- If an older account reports a workspace or user mismatch, sign in to that account again to replace its cached credentials.
