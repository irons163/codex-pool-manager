#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-CodexPoolManager}"
SCHEME="${SCHEME:-CodexPoolManager}"
PROJECT_PATH="${PROJECT_PATH:-CodexPoolManager.xcodeproj}"
CONFIGURATION="${CONFIGURATION:-Release}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
VERSION="${VERSION:-${GITHUB_REF_NAME:-$(date +%Y.%m.%d.%H%M)}}"

WORK_DIR="$(pwd)/build/release"
ARCHIVE_PATH="$WORK_DIR/${APP_NAME}.xcarchive"
STAGING_DIR="$WORK_DIR/staging"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$WORK_DIR/${DMG_NAME}"

rm -rf "$WORK_DIR" dist
mkdir -p "$WORK_DIR" "$STAGING_DIR" dist

echo "==> Archiving app"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  archive

APP_PATH="$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Archive did not produce ${APP_NAME}.app at expected path: $APP_PATH" >&2
  exit 1
fi

echo "==> Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Creating DMG"
cp -R "$APP_PATH" "$STAGING_DIR/"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "==> Notarizing DMG"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"

cp "$DMG_PATH" "dist/${DMG_NAME}"
echo "DMG ready: dist/${DMG_NAME}"
