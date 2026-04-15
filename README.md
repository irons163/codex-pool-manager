# Codex Pool Manager

Codex Pool Manager is a macOS app for operating a pool of Codex/OpenAI OAuth accounts from one control panel.

It helps you:
- track quota and remaining usage per account,
- switch the active auth account quickly,
- auto-rotate accounts with an intelligent policy,
- monitor status from Desktop Widget and Menu Bar,
- keep backup/export flows for recovery.

Languages: [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Español](README.es.md)

## Table of Contents

1. [Screenshots](#screenshots)
2. [Key Features](#key-features)
3. [How Intelligent Switching Works](#how-intelligent-switching-works)
4. [Widget + Menu Bar](#widget--menu-bar)
5. [Authentication and Account Import](#authentication-and-account-import)
6. [Workspaces](#workspaces)
7. [Install](#install)
8. [Build From Source](#build-from-source)
9. [Release DMG Pipeline](#release-dmg-pipeline)
10. [Project Structure](#project-structure)
11. [Testing](#testing)
12. [Troubleshooting](#troubleshooting)
13. [Security and Privacy Notes](#security-and-privacy-notes)
14. [Contributing](#contributing)

## Screenshots

All screenshots below use mock or non-sensitive test data.

### App Icon (Current)

![App Icon](docs/images/app-icon.png)

### Main Dashboard (Dark, Mock Data)

![Main Dashboard (Dark, Mock Data)](docs/images/app-screenshot.png)

### Header Overview (Light, Mock Data)

![Header Overview (Light, Mock Data)](docs/images/dashboard-light.png)

### Menu Bar Status (Mock Data)

![Menu Bar Status](docs/images/menu-bar.png)

### Widget (Empty-State Example, Mock State)

![Widget Empty State](docs/images/widget-empty-state.png)

### OpenAI Reset Alert (Mock Data)

![OpenAI Reset Alert](docs/images/openai-reset-alert.png)

## Key Features

### 1) Account pool management

- Add, edit, duplicate, and remove accounts.
- Group accounts and manage groups (`Add`, `Rename`, `Delete`).
- Group deletion removes all accounts in that group.
- Sort and layout controls for large pools.
- Dedup-aware pool statistics (`Accounts`, `Available`, `Pool Usage`) to avoid counting duplicated identities multiple times.

### 2) Multiple switch modes

- `Intelligent`: auto-selects the best account based on remaining capacity and policy thresholds.
- `Manual`: sticks to the account you manually choose.
- `Focus`: pins to the current account and avoids intelligent auto-rotation.

### 3) Usage sync and diagnostics

- Sync usage from Codex/OpenAI endpoints for all eligible accounts.
- Handles sync exclusions (missing token, missing account id, API/network errors).
- Shows last successful sync time and sync error details.
- Includes raw usage JSON and switch logs for diagnostics.

### 4) OAuth sign-in flows

- In-app OAuth sign-in and direct import.
- Manual flow: copy authorization URL, paste callback URL, then import.
- Local auth discovery from common local paths.
- Import local OAuth sessions/accounts into managed pool.

### 5) Desktop integration

- Native macOS notifications for key events (sync failure/recovery, low usage, auto-switch outcomes).
- Menu Bar extra that shows live remaining usage summary.
- macOS Widget extension for quick status glance.

### 6) Backup and restore

- Export JSON snapshot.
- Export refetchable snapshot (sensitive; includes fields needed for re-fetch workflows).
- Import JSON snapshot for migration/recovery.

### 7) UI and localization

- Dark mode + light mode.
- Language switching via app settings.
- Locale-aware time formatting for app/widget texts.

### 8) Usage analytics and schedule planning

- Dedicated `Schedule` workspace for reset timeline planning across accounts.
- Daily/weekly usage analytics to identify consumption patterns.
- Coverage view to highlight potential uncovered windows between account resets.
- Per-account trend lines, threshold events, and anomaly summaries.
- Export analytics as JSON/CSV for reporting or external analysis.

### 9) OpenAI reset monitoring

- Dedicated `OpenAI Reset Alert` workspace for paid-account reset tracking.
- Monitors weekly reset and 5-hour reset targets together.
- Flags early reset signals when resets move earlier than expected (within configurable tolerance).
- Optional desktop notifications and event history for auditability.

## How Intelligent Switching Works

This section explains the exact runtime behavior so release users understand what to expect.

### Account eligibility

Only accounts that are **not excluded from sync/scheduling** are considered for automatic switching.

Examples of exclusion reasons:
- missing API token,
- missing ChatGPT account id,
- sync error status.

### Paid vs non-paid remaining logic

- Non-paid account: intelligent remaining is based on weekly remaining ratio (`remainingUnits / quota`).
- Paid account (default): intelligent remaining uses the **5-hour remaining** percentage.
- Paid account special case: if weekly remaining is already `0%`, weekly remaining is treated as source of truth (account is effectively exhausted).

### Candidate selection

From eligible accounts, the engine chooses the best candidate by highest intelligent remaining ratio.

Accounts with weekly remaining `<= 0` are not eligible candidates.

### Switch trigger conditions

In `Intelligent` mode, switching happens only when all are true:

1. there is a valid candidate;
2. current active account is low enough (below intelligent switch threshold);
3. candidate is better than current;
4. cooldown interval has elapsed.

### Focus mode behavior

When switching into `Focus`, current account is pinned to prevent unexpected jumps.
No intelligent auto-switch is performed in focus mode.

### Low-usage alert threshold is separate

There are two different thresholds:

- Intelligent switch threshold: controls **when switching is allowed**.
- Low remaining usage alert threshold: controls **when warning/notification is shown**.

These are intentionally independent.

## Widget + Menu Bar

### Widget

- Widget reads snapshot from local bridge endpoint exposed by the main app.
- If no snapshot is available, widget shows a friendly empty-state prompt.
- Timeline refresh policy:
  - around every `60s` when snapshot exists,
  - around every `10s` when snapshot is missing.

### Menu Bar

- Menu bar title contains compact status (remaining %, paid 5h left, update age).
- Menu content shows active account details, reset times, and update age.
- Refreshes periodically (every ~15s) and supports manual refresh.

## Authentication and Account Import

### Local account discovery paths

The app scans local auth JSON from common locations:

- `~/.codex/auth.json`
- `~/.config/codex/auth.json`
- `~/.openai/auth.json`

### Public OAuth client

By default, the app supports public client flow and also allows your own OAuth client parameters.

### Manual callback flow

If browser callback cannot complete directly in-app:

1. click `Copy URL and Manual sign in`;
2. complete sign-in in browser;
3. paste callback URL into the callback field;
4. click `Import`.

## Workspaces

The UI is organized into workspaces for clearer operational boundaries.

### Authentication

- OAuth sign-in panel
- Advanced OAuth parameters
- Local OAuth account scanning/import

### Runtime Strategy

- mode selector (`Intelligent`, `Manual`, `Focus`)
- intelligent switch threshold
- low-usage alert threshold
- smart recommendation panel

### Schedule

- reset timeline overview across managed accounts
- daily/weekly usage analytics summaries
- coverage gap hints for planning account usage
- per-account trend lines and threshold/anomaly events
- analytics export (`Copy JSON`, `Export CSV`, `Export JSON`)

### OpenAI Reset Alert

- paid-account reset target tracking
- early-reset tolerance configuration
- early-reset signal detection summary and records
- optional desktop alerting + event list management

### Settings

- launch behavior
- auto-sync toggle + interval
- language
- appearance (system/dark/light)

### Safety

- backup/export/import controls
- diagnostics surface for raw data/log verification

## Install

### Option A: Download prebuilt DMG from Releases

Release assets provide two architecture-specific DMGs:

- `CodexPoolManager-<version>-apple-silicon.dmg`
- `CodexPoolManager-<version>-intel.dmg`

Pick the one matching your Mac architecture.

### Option B: Run from source in Xcode

See next section.

## Build From Source

### Requirements

- macOS
- Xcode 16+

### Steps

```bash
cd /path/to/AIAgentPool
open CodexPoolManager.xcodeproj
```

In Xcode:

1. Select the `CodexPoolManager` scheme.
2. Choose your local Mac destination.
3. Build and Run.

If you also need widget testing, make sure widget-related targets are signed with the same team where required.

## Release DMG Pipeline

Automated DMG packaging + notarization is configured in:

- `.github/workflows/release-dmg.yml`
- `scripts/build_and_notarize_dmg.sh`

### Pipeline highlights

- Builds both `arm64` and `x86_64` variants.
- Uses release version/tag for artifact naming (not commit hash).
- Signs with Developer ID Application certificate.
- Notarizes and staples each DMG.
- Uploads DMGs to both workflow artifacts and GitHub Release assets.

### Required GitHub secrets

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`
- `APPLE_API_PRIVATE_KEY_BASE64`

For detailed setup docs, see [RELEASE_DMG.md](RELEASE_DMG.md).

## Project Structure

```text
AIAgentPool/
├─ CodexPoolManager/                 # Main macOS app target
├─ CodexPoolWidget/                  # Widget extension target
├─ CodexPoolWidgetHost/              # Companion host target for widget bridging/testing
├─ Domain/Pool/                      # Core state, switching rules, snapshot model
├─ Features/PoolDashboard/           # UI + flow coordinators
├─ Infrastructure/Auth/              # OAuth, auth file access/switch services
├─ Infrastructure/Usage/             # Usage sync client/service
├─ CodexPoolManagerTests/            # Unit tests
├─ CodexPoolManagerUITests/          # UI tests
├─ .github/workflows/release-dmg.yml # Release workflow
└─ scripts/build_and_notarize_dmg.sh # Local/CI DMG script
```

## Testing

Run tests in Xcode, or via command line:

```bash
xcodebuild \
  -project CodexPoolManager.xcodeproj \
  -scheme CodexPoolManager \
  -destination 'platform=macOS' \
  test
```

## Troubleshooting

### "Syncing..." appears stuck

- Confirm network/API availability.
- Check Sync Error callout for details.
- Ensure active accounts have valid token and account id.
- Try manual sync again after a short interval.

### Widget shows "No snapshot available"

- Open CodexPoolManager once (widget bridge is published by main app).
- Wait a few seconds and refresh widget.
- Verify local firewall/network rules do not block localhost loopback.

### Local OAuth scan finds nothing

- Use `Choose auth.json` and grant permission manually.
- Verify auth data exists in one of the known candidate paths.

### Account not switching in Intelligent mode

- Check whether current remaining is below switch threshold.
- Check cooldown interval.
- Check candidate account eligibility and remaining values.
- In focus mode, intelligent switching is intentionally disabled.

## Security and Privacy Notes

- Refetchable exports may contain sensitive values.
- Do not share raw logs or exports publicly without redaction.
- Use secure storage for internal snapshots.
- OAuth/client credentials should be handled according to your security policy.

## Contributing

Issues and PRs are welcome.

Recommended PR scope:
- one behavior change per PR,
- include test coverage for domain or coordinator logic,
- include before/after screenshots for UI changes.

---

If this project helps your Codex account operations, consider starring the repository.
