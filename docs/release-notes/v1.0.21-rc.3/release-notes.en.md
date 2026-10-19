# CodexPoolManager v1.0.21-rc.3

Release date: 2026-10-19

## Fixes

- Highlight only the selected account card as current, even when multiple members share an enterprise workspace or older records contain copied credentials.
- Match OAuth credentials to both workspace and user identity during local recovery, import, refresh, switching, and credential checkpoints.
- Reject another member's cached credentials and display a clear user mismatch message for affected records. Signing in again updates the matching member instead of another account in the same workspace.
- Keep the business account badges and linked session directory fixes from earlier prereleases.

## Prerelease Note

- If an earlier prerelease assigned another member's credentials to an account, sign in to the affected account again after updating.
