# CodexPoolManager v1.0.21-rc.4

Release date: 2026-10-19

## Fixes

- Read complete session log snapshots instead of stopping at 128 MiB per file, restoring usage events at the end of large logs.
- Stream logs in small chunks and skip conversation bodies early while retaining bounded metadata buffers and cancellation support.
- Recognize actual metadata types instead of matching keywords in tool output, avoiding false incomplete-statistics warnings when large outputs mention token_count.
- Keep workspace member isolation, Business badges, and linked session directory support from earlier prereleases.

## Prerelease Note

- Genuine unreadable files, unresolved fork sources, and usage-event limits still produce an incomplete-statistics warning.
