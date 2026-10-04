# CodexPoolManager v1.0.20-rc.7

Release date: 2026-10-05

## Changes

- Save refreshed OAuth credentials before fetching usage, so a later usage error or cancellation does not discard rotated tokens.
- Distinguish confirmed credential rejection from network failures, rate limits, service errors, and missing refresh tokens instead of reporting every refresh failure as an expired login.
- Prevent delayed refresh results from overwriting reimported credentials or restoring deleted accounts.
- Change the OpenAI Reset Alert badge to “Removing soon” in all supported languages. The feature remains available in this prerelease.
- Add regression coverage for token rotation, error classification, cancellation, and stale refresh results.

## Prerelease Note

- This prerelease validates OAuth refresh reliability before stable v1.0.20. Credentials that have actually been revoked still require signing in again.
