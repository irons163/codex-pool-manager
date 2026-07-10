# CodexPoolManager v1.0.16

Release date: 2026-07-11

## Highlights

- Reset-credit expiry dates now come directly from the exact `expires_at` values returned by the Codex account details API instead of being inferred from the last successful sync.
- Account cards, the menu bar dashboard, and reset alerts use exact API dates whenever they are available.
- API-provided dates no longer show the estimated-date warning; the warning appears only when the fallback estimate is required.
- Expiry provenance is preserved in account snapshots so exact API dates remain distinguishable from estimates after relaunching.
- The README and all supported interface localizations now explain exact API dates and fallback estimates consistently.

## Reliability and Compatibility

- The existing estimate remains available automatically when account details or expiry dates cannot be retrieved.
- Snapshots created by earlier versions remain compatible and are treated conservatively as estimated data.
- This stable release rolls up the changes validated in v1.0.15-rc.1.
