# CodexPoolManager v1.0.15-rc.1

Release date: 2026-07-11

## Improvements

- Reset-credit expiry dates now come directly from the `expires_at` values returned by the dedicated Codex account details endpoint instead of being inferred from the last successful sync.
- Account cards and reset alerts use the exact API dates whenever they are available.
- API-provided dates no longer show the estimated-date warning; the warning appears only when the app must use its fallback estimate.
- Expiry provenance is preserved in account snapshots so the interface can distinguish exact API dates from fallback estimates after relaunching.
- The README and all supported interface localizations now explain exact API dates and fallback estimates consistently.

## Compatibility

- The existing estimate remains available when account details or expiry dates cannot be retrieved.
- Snapshots created by earlier versions remain compatible and are treated conservatively as estimated data.

## Prerelease Note

- This prerelease validates exact reset-credit expiry synchronization and the unavailable-data fallback before the next stable rollout.
