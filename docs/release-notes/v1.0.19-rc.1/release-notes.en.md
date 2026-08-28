# CodexPoolManager v1.0.19-rc.1

Release date: 2026-08-28

## Fixes

- Account switching now closes Codex before rewriting credentials, so a live session is not treated as revoked.
- Switch writes the target account’s refresh/id tokens instead of leaving the previous account’s tokens in `auth.json`.
- Credentials are also updated in the Codex Keychain store and the `current_account` mirror used by newer Codex builds.

## Prerelease Note

- This prerelease validates account switching against the post-update Codex login flow before the stable rollout.
