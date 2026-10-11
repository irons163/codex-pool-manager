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

(
  export OUTPUT_DIR="${TMP_DIR}/special-characters"
  export APP_NAME='Codex & <Pool> "Manager"'
  export RELEASE_TAG='v9.8.7'
  export BUILD_VERSION='112'
  export RELEASE_NAME='Update & <fix> "A"'
  export RELEASE_NOTES='修正 A & B，保留 ]]> 與第二個 ]]> 分隔符號。'
  export PUBLISHED_AT='2026-06-09T09:05:30Z'
  export ARM64_URL='https://example.com/apple-silicon.dmg?arch=arm64&download=1'
  export ARM64_SIZE='123'
  export X86_64_URL='https://example.com/intel.dmg?arch=x86_64&download=1'
  export X86_64_SIZE='456'
  export LOCALIZED_RELEASE_NOTES_LINKS='zh-Hant=https://example.com/notes?language=zh-Hant&full=1'
  export MAX_NOTES_CHARS='2800'

  "${ROOT_DIR}/scripts/generate_sparkle_appcast.sh" >/dev/null

  python3 - <<'PY'
import os
from pathlib import Path
import xml.etree.ElementTree as ET

sparkle = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
for arch, prefix in (("arm64", "ARM64"), ("x86_64", "X86_64")):
    feed = ET.parse(Path(os.environ["OUTPUT_DIR"]) / f"appcast-{arch}.xml")
    channel = feed.getroot().find("channel")
    item = channel.find("item")
    enclosure = item.find("enclosure")
    assert channel.findtext("title") == f'{os.environ["APP_NAME"]} Updates ({arch})'
    assert channel.findtext("description") == f'Latest {os.environ["APP_NAME"]} updates for {arch}'
    assert item.findtext("title") == os.environ["RELEASE_NAME"]
    assert item.findtext("description") == os.environ["RELEASE_NOTES"]
    assert enclosure.get("url") == os.environ[prefix + "_URL"]
    assert enclosure.get("length") == os.environ[prefix + "_SIZE"]
    assert enclosure.get(sparkle + "version") == os.environ["BUILD_VERSION"]
    assert enclosure.get(sparkle + "shortVersionString") == "9.8.7"
    notes_link = item.find(sparkle + "releaseNotesLink")
    assert notes_link.get("{http://www.w3.org/XML/1998/namespace}lang") == "zh-Hant"
    assert notes_link.text == os.environ["LOCALIZED_RELEASE_NOTES_LINKS"].split("=", 1)[1]
PY
)

echo "generate_sparkle_appcast localized notes and XML round-trip tests passed"
