# CodexPoolManager v1.0.14

Release date: 2026-06-10

## Fixes

- Bypassed the production async dependency-injection closure for relay API key login, so the login service receives the already validated request key instead of an empty Data value in release builds.
- Added deeper relay API key auth diagnostics that record app version/build, login-service input lengths, and sanitized auth.json write stages without exposing API key values.
- Passed the token-vault API key directly into relay switch requests, so stale or redacted SwiftUI state can no longer make an existing relay key look missing.
- Relay API key accounts now write their key to the token vault immediately when added, so switching to a relay account right after creating it no longer fails with a "missing API key" error.
- Stopped `save()` from pruning the token vault. A stale or empty in-memory snapshot (for example a save during startup) could previously delete still-valid relay and ChatGPT (OAuth) API keys permanently, with no way to recover because the persisted snapshot is redacted. Tokens are now removed only through the explicit account or group delete flow.
- Resolved relay API key tokens directly from the active token vault by account ID before switching, so redacted snapshots can no longer be mistaken for missing API keys.
- Restored relay API key tokens from the persisted token vault before switching when the in-memory dashboard state only has the redacted account snapshot.
- Relay API key switching now writes Codex's API-key `auth.json` directly instead of invoking Codex CLI through stdin, avoiding release-only stdin handoff failures that made existing keys look missing.
- Hardened relay API key account switching by snapshotting account, provider, and API key data before the async switch flow. This targets the release-only crash observed in v1.0.13.
- Moved relay API key form readiness checks out of SwiftUI body rendering to avoid extra string trimming during view updates.
- Added a sanitized relay switch diagnostic log that records account IDs, token lengths, and switch stages without storing API key values, so release-only missing-key reports can be traced precisely.

## Notes

- No account, API key, auth.json, or config.toml migration is required.
- This prerelease is intended to validate the relay API key switching hotfix before the stable rollout.
- Prerelease builds now include matching dSYM artifacts on GitHub Releases to support symbolicated crash diagnostics.
