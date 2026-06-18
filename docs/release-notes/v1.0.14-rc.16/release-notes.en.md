# CodexPoolManager v1.0.14-rc.16

Release date: 2026-06-18

## Fixes

- OAuth ChatGPT accounts now preserve refresh token, ID token, and last refresh time in the token vault.
- Usage sync retries once after a 401/403 response by refreshing the OAuth access token first.
- Local auth.json import now carries refresh and ID tokens into managed OAuth accounts.
- Sync merge no longer overwrites a newer local credential with an older sync snapshot.

## Notes

- This prerelease is for validating OAuth account refresh stability before a stable rollout.
- No relay API key, config.toml, or auth.json migration is required.
