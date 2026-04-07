#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-CodexPoolManager}"
SCHEME="${SCHEME:-CodexPoolManager}"
PROJECT_PATH="${PROJECT_PATH:-CodexPoolManager.xcodeproj}"
CONFIGURATION="${CONFIGURATION:-Release}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
VERSION="${VERSION:-${GITHUB_REF_NAME:-$(date +%Y.%m.%d.%H%M)}}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
ARCHS="${ARCHS:-}"
ARCH_LABEL="${ARCH_LABEL:-}"

WORK_DIR="$(pwd)/build/release"
ARCHIVE_PATH="$WORK_DIR/${APP_NAME}.xcarchive"
STAGING_DIR="$WORK_DIR/staging"
SAFE_VERSION="$(sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^-+//; s/-+$//' <<<"$VERSION")"
if [[ -z "$SAFE_VERSION" ]]; then
  SAFE_VERSION="0.0.0"
fi
if [[ -n "$ARCH_LABEL" ]]; then
  DMG_SUFFIX="-$ARCH_LABEL"
elif [[ -n "$ARCHS" ]]; then
  DMG_SUFFIX="-$ARCHS"
else
  DMG_SUFFIX=""
fi
DMG_NAME="${APP_NAME}-${SAFE_VERSION}${DMG_SUFFIX}.dmg"
DMG_PATH="$WORK_DIR/${DMG_NAME}"

rm -rf "$WORK_DIR" dist
mkdir -p "$WORK_DIR" "$STAGING_DIR" dist

if [[ -z "$DEVELOPMENT_TEAM" ]]; then
  echo "DEVELOPMENT_TEAM is required for archive signing." >&2
  exit 1
fi

echo "==> Archiving app"
XCODEBUILD_ARGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "generic/platform=macOS"
  -archivePath "$ARCHIVE_PATH"
  CODE_SIGN_STYLE=Manual
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY"
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime"
  ENABLE_HARDENED_RUNTIME=YES
  CODE_SIGNING_REQUIRED=YES
  CODE_SIGNING_ALLOWED=YES
  archive
)
if [[ -n "$ARCHS" ]]; then
  XCODEBUILD_ARGS+=(ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO)
fi
xcodebuild "${XCODEBUILD_ARGS[@]}"

APP_PATH="$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Archive did not produce ${APP_NAME}.app at expected path: $APP_PATH" >&2
  exit 1
fi

APP_BINARY="$APP_PATH/Contents/MacOS/$APP_NAME"
if [[ ! -f "$APP_BINARY" ]]; then
  APP_BINARY="$(find "$APP_PATH/Contents/MacOS" -maxdepth 1 -type f | head -n 1)"
fi
if [[ ! -f "$APP_BINARY" ]]; then
  echo "Unable to locate app executable in archive." >&2
  exit 1
fi
APP_BINARY_ARCHS="$(lipo -archs "$APP_BINARY" 2>/dev/null || true)"
echo "Built app binary architectures: ${APP_BINARY_ARCHS:-unknown}"
if [[ -n "$ARCHS" ]]; then
  for expected_arch in $ARCHS; do
    if ! grep -qw "$expected_arch" <<<"$APP_BINARY_ARCHS"; then
      echo "Archive binary is missing expected architecture: $expected_arch" >&2
      exit 1
    fi
  done
fi

echo "==> Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNATURE_DETAILS="$(codesign -d --verbose=4 "$APP_PATH" 2>&1 || true)"
echo "$SIGNATURE_DETAILS"

if ! grep -q "Authority=Developer ID Application" <<<"$SIGNATURE_DETAILS"; then
  echo "Code signing identity is not Developer ID Application." >&2
  exit 1
fi

if ! grep -q "Timestamp=" <<<"$SIGNATURE_DETAILS"; then
  echo "Code signature is missing secure timestamp." >&2
  exit 1
fi

if ! grep -q "Runtime Version=" <<<"$SIGNATURE_DETAILS"; then
  echo "Hardened runtime is not enabled in code signature." >&2
  exit 1
fi

echo "==> Creating DMG"
cp -R "$APP_PATH" "$STAGING_DIR/"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "==> Notarizing DMG"
NOTARY_OUTPUT="$(xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)"
echo "$NOTARY_OUTPUT"

if ! grep -qE 'status:[[:space:]]+Accepted' <<<"$NOTARY_OUTPUT"; then
  SUBMISSION_ID="$(sed -n 's/^[[:space:]]*id:[[:space:]]*//p' <<<"$NOTARY_OUTPUT" | head -n 1)"
  if [[ -n "$SUBMISSION_ID" ]]; then
    echo "==> Fetching notarization log"
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" || true
  fi
  echo "Notarization failed (status is not Accepted)." >&2
  exit 1
fi

echo "==> Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"

cp "$DMG_PATH" "dist/${DMG_NAME}"
echo "DMG ready: dist/${DMG_NAME}"
