# CodexPoolManager v1.0.14

Release date: 2026-06-10

## Fixes

- Resolved relay API key tokens directly from the active token vault by account ID before switching, so redacted snapshots can no longer be mistaken for missing API keys.
- Restored relay API key tokens from the persisted token vault before switching when the in-memory dashboard state only has the redacted account snapshot.
- Normalized the relay API key stdin payload before calling `codex login --with-api-key`: empty keys are rejected before launching Codex CLI, and valid keys are sent as owned bytes with a trailing newline.
- Hardened relay API key account switching by snapshotting account, provider, and API key data before the async switch flow. This targets the release-only crash observed in v1.0.13.
- Avoided the release-only relay switch crash by passing prepared API key bytes into the Codex CLI login flow instead of trimming the API key string inside the async login closure.
- Moved relay API key form readiness checks out of SwiftUI body rendering to avoid extra string trimming during view updates.

## Notes

- No account, API key, auth.json, or config.toml migration is required.
- This prerelease is intended to validate the relay API key switching hotfix before the stable rollout.
- Prerelease builds now include matching dSYM artifacts on GitHub Releases to support symbolicated crash diagnostics.
