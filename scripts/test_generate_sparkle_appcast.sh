#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_contains() {
  local file="$1"
  local expected="$2"

  if ! grep -Fq "$expected" "$file"; then
    echo "Expected to find:" >&2
    echo "$expected" >&2
    echo "In ${file}:" >&2
    cat "$file" >&2
    exit 1
  fi
}

TEST_PRIVATE_KEY="$(python3 -c 'import base64; print(base64.b64encode(bytes(range(32))).decode())')"
printf 'arm64 dummy dmg content' > "$TMP_DIR/arm64.dmg"
printf 'intel dummy dmg content' > "$TMP_DIR/intel.dmg"

OUTPUT_DIR="$TMP_DIR" \
RELEASE_TAG="v9.8.7" \
BUILD_VERSION="112" \
RELEASE_NAME="CodexPoolManager v9.8.7" \
RELEASE_NOTES=$'# CodexPoolManager v9.8.7\n\nFallback notes.' \
PUBLISHED_AT="2026-06-09T09:05:30Z" \
ARM64_URL="https://example.com/CodexPoolManager-9.8.7-apple-silicon.dmg" \
ARM64_SIZE="123" \
ARM64_FILE="$TMP_DIR/arm64.dmg" \
X86_64_URL="https://example.com/CodexPoolManager-9.8.7-intel.dmg" \
X86_64_SIZE="456" \
X86_64_FILE="$TMP_DIR/intel.dmg" \
LOCALIZED_RELEASE_NOTES_LINKS=$'en=https://example.com/release-notes.en.md\nzh-Hant=https://example.com/release-notes.zh-Hant.md\nja=https://example.com/release-notes.ja.md' \
SPARKLE_PRIVATE_KEY="$TEST_PRIVATE_KEY" \
"${ROOT_DIR}/scripts/generate_sparkle_appcast.sh" >/dev/null

ARM64_APPCAST="${TMP_DIR}/appcast-arm64.xml"
X86_64_APPCAST="${TMP_DIR}/appcast-x86_64.xml"

assert_contains "$ARM64_APPCAST" '<description sparkle:format="plain-text"><![CDATA[CodexPoolManager v9.8.7'
assert_contains "$ARM64_APPCAST" 'sparkle:version="112"'
assert_contains "$ARM64_APPCAST" 'sparkle:edSignature="'
assert_contains "$ARM64_APPCAST" '<sparkle:releaseNotesLink xml:lang="en">https://example.com/release-notes.en.md</sparkle:releaseNotesLink>'
assert_contains "$ARM64_APPCAST" '<sparkle:releaseNotesLink xml:lang="zh-Hant">https://example.com/release-notes.zh-Hant.md</sparkle:releaseNotesLink>'
assert_contains "$ARM64_APPCAST" '<sparkle:releaseNotesLink xml:lang="ja">https://example.com/release-notes.ja.md</sparkle:releaseNotesLink>'
assert_contains "$X86_64_APPCAST" '<sparkle:releaseNotesLink xml:lang="zh-Hant">https://example.com/release-notes.zh-Hant.md</sparkle:releaseNotesLink>'
assert_contains "$X86_64_APPCAST" 'sparkle:edSignature="'

python3 - "$ARM64_APPCAST" "$TMP_DIR/arm64.dmg" "$TEST_PRIVATE_KEY" <<'PY'
import base64
import re
import sys
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

xml = Path(sys.argv[1]).read_text()
signature = base64.b64decode(
    re.search(r'sparkle:edSignature="([^"]+)"', xml).group(1)
)
seed = base64.b64decode(sys.argv[3])
Ed25519PrivateKey.from_private_bytes(seed).public_key().verify(
    signature,
    Path(sys.argv[2]).read_bytes(),
)
PY

echo "generate_sparkle_appcast localized release notes and signing test passed"
