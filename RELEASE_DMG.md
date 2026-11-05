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
- `SPARKLE_PRIVATE_KEY`

Notes:

- `APPLE_CERTIFICATE_P12_BASE64`: Base64-encoded `Developer ID Application` certificate (`.p12`)
- `APPLE_API_PRIVATE_KEY_BASE64`: Base64-encoded App Store Connect API key (`.p8`)
- `SPARKLE_PRIVATE_KEY`: Base64-encoded Ed25519 private key (32-byte seed) used to sign Sparkle update archives. Generate it with Sparkle's `generate_keys`, export it with `generate_keys -x <file>`, and store the file contents as this secret. The matching public key must be embedded in the app as `SUPublicEDKey`.

### Sparkle EdDSA signing

`scripts/generate_sparkle_appcast.sh` downloads each DMG, signs it with `SPARKLE_PRIVATE_KEY`, and writes the `sparkle:edSignature` attribute into the appcast enclosure. The `publish-sparkle-appcast` job requires the secret and installs the Python `cryptography` package to perform the signature.

When rotating keys, first ship a release that embeds the new `SUPublicEDKey`, then switch the appcast signatures. Installs that predate `SUPublicEDKey` cannot be updated through Sparkle and require one manual install.

## 2. Release Trigger

The workflow runs when:

- A GitHub Release is published
- Manually via `workflow_dispatch`

## 3. Output

On success, it will:

1. Archive the macOS app in `Release`
2. Build a `.dmg`
3. Notarize and staple the DMG
4. Upload localized release note assets from `docs/release-notes/v<version>/release-notes.<lang>.md`
5. Upload the DMG as:
   - Workflow artifact
   - GitHub Release asset (for release events)
6. Generate and upload Sparkle appcast XML assets that link to localized release notes

Localized release note assets are required for release/tag builds. The currently supported files are:

- `release-notes.en.md`
- `release-notes.zh-Hant.md`
- `release-notes.zh-Hans.md`
- `release-notes.ja.md`
- `release-notes.ko.md`
- `release-notes.fr.md`
- `release-notes.es.md`

The appcast generator includes these assets as Sparkle `releaseNotesLink` entries with `xml:lang`, so Sparkle can show localized update notes in its built-in update dialog. The GitHub Release body remains the English fallback description.

Sparkle compares `sparkle:version` against the app bundle build number (`CURRENT_PROJECT_VERSION` / `CFBundleVersion`). The workflow reads that value from the Xcode project when generating appcasts; do not derive it from the release tag.

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
