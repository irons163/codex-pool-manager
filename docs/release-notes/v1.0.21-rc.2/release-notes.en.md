# CodexPoolManager v1.0.21-rc.2

Release date: 2026-10-19

## Fixes

- Resolve symbolic links before scanning session directories, restoring analytics when Codex sessions are stored on an external drive or reached through a linked source folder.
- Scan each physical directory once when sessions and archived sessions point to the same location, avoiding duplicate work and premature scan limits.
- Retain the workspace credential fixes and Business badges introduced in rc.1.

## Prerelease Note

- Large logs can still reach the existing read limits; partial statistics remain clearly marked instead of being presented as complete.
