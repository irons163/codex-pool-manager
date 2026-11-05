# CodexPoolManager v1.0.24-rc.4

Release date: 2026-11-05

## New Features

- Added an `Ordered` switch mode: arrange accounts in the execution strategy page and rotate through them in that order, wrapping back to the first after the last account.
- The switch threshold also applies to the ordered mode, and sync-excluded or Relay accounts are skipped automatically.

## Improvements

- When sorting by remaining usage, expired or sync-excluded accounts now sink below healthy accounts while the active account stays first.
- Business accounts now use purple badges to distinguish them from personal accounts.
- The ordered switch list now supports drag-and-drop reordering; the up/down buttons remain available for fine tuning.
- The ordered switch list now seeds by actual switch availability: healthy accounts come before exhausted ones, while excluded accounts stay last.
- Order rows now show plan and workspace scope, so accounts sharing the same email can be distinguished.

## Fixes

- Distinguish revoked credentials from other sync errors and recover automatically after token rotation.
- Fixed Sparkle update verification by embedding the EdDSA public key and signing release archives.

## Removals

- Removed the `OpenAI Reset Alert` workspace along with its notifications, monitoring state, and related settings.

## Notes

- Builds created before the Sparkle public key was embedded must install this version manually once. Subsequent updates verify automatically.
