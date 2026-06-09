# CodexPoolManager v1.0.14

Release date: 2026-06-09

## Fixes

- Hardened relay API key account switching by snapshotting account, provider, and API key data before the async switch flow. This targets the release-only crash observed in v1.0.13.
- Moved relay API key form readiness checks out of SwiftUI body rendering to avoid extra string trimming during view updates.

## Notes

- No account, API key, auth.json, or config.toml migration is required.
- This prerelease is intended to validate the relay API key switching hotfix before the stable rollout.
