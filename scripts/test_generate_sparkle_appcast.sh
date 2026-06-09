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

OUTPUT_DIR="$TMP_DIR" \
RELEASE_TAG="v9.8.7" \
BUILD_VERSION="112" \
RELEASE_NAME="CodexPoolManager v9.8.7" \
RELEASE_NOTES=$'# CodexPoolManager v9.8.7\n\nFallback notes.' \
PUBLISHED_AT="2026-06-09T09:05:30Z" \
ARM64_URL="https://example.com/CodexPoolManager-9.8.7-apple-silicon.dmg" \
ARM64_SIZE="123" \
X86_64_URL="https://example.com/CodexPoolManager-9.8.7-intel.dmg" \
X86_64_SIZE="456" \
LOCALIZED_RELEASE_NOTES_LINKS=$'en=https://example.com/release-notes.en.md\nzh-Hant=https://example.com/release-notes.zh-Hant.md\nja=https://example.com/release-notes.ja.md' \
"${ROOT_DIR}/scripts/generate_sparkle_appcast.sh" >/dev/null

ARM64_APPCAST="${TMP_DIR}/appcast-arm64.xml"
X86_64_APPCAST="${TMP_DIR}/appcast-x86_64.xml"

assert_contains "$ARM64_APPCAST" '<description sparkle:format="plain-text"><![CDATA[CodexPoolManager v9.8.7'
assert_contains "$ARM64_APPCAST" 'sparkle:version="112"'
assert_contains "$ARM64_APPCAST" '<sparkle:releaseNotesLink xml:lang="en">https://example.com/release-notes.en.md</sparkle:releaseNotesLink>'
assert_contains "$ARM64_APPCAST" '<sparkle:releaseNotesLink xml:lang="zh-Hant">https://example.com/release-notes.zh-Hant.md</sparkle:releaseNotesLink>'
assert_contains "$ARM64_APPCAST" '<sparkle:releaseNotesLink xml:lang="ja">https://example.com/release-notes.ja.md</sparkle:releaseNotesLink>'
assert_contains "$X86_64_APPCAST" '<sparkle:releaseNotesLink xml:lang="zh-Hant">https://example.com/release-notes.zh-Hant.md</sparkle:releaseNotesLink>'

echo "generate_sparkle_appcast localized release notes test passed"
