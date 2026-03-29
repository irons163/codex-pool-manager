# DMG Release Pipeline

This repository includes automated DMG packaging and notarization via:

- `.github/workflows/release-dmg.yml`
- `scripts/build_and_notarize_dmg.sh`

## 1. Required GitHub Secrets

Add these repository secrets:

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`
- `APPLE_API_PRIVATE_KEY_BASE64`

Notes:

- `APPLE_CERTIFICATE_P12_BASE64`: Base64-encoded `Developer ID Application` certificate (`.p12`)
- `APPLE_API_PRIVATE_KEY_BASE64`: Base64-encoded App Store Connect API key (`.p8`)

## 2. Release Trigger

The workflow runs when:

- A GitHub Release is published
- Manually via `workflow_dispatch`

## 3. Output

On success, it will:

1. Archive the macOS app in `Release`
2. Build a `.dmg`
3. Notarize and staple the DMG
4. Upload the DMG as:
   - Workflow artifact
   - GitHub Release asset (for release events)

## 4. Local Execution (optional)

If your local machine is already configured with signing + notarization profile:

```bash
chmod +x scripts/build_and_notarize_dmg.sh
APP_NAME=CodexPoolManager \
SCHEME=CodexPoolManager \
PROJECT_PATH=CodexPoolManager.xcodeproj \
VERSION=v1.0.0 \
NOTARY_PROFILE=AC_NOTARY \
scripts/build_and_notarize_dmg.sh
```
