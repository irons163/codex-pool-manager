#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${OUTPUT_DIR:-dist}"
APP_NAME="${APP_NAME:-CodexPoolManager}"
RELEASE_TAG="${RELEASE_TAG:-}"
RELEASE_NAME="${RELEASE_NAME:-}"
RELEASE_NOTES="${RELEASE_NOTES:-}"
PUBLISHED_AT="${PUBLISHED_AT:-}"
ARM64_URL="${ARM64_URL:-}"
ARM64_SIZE="${ARM64_SIZE:-}"
X86_64_URL="${X86_64_URL:-}"
X86_64_SIZE="${X86_64_SIZE:-}"
MAX_NOTES_CHARS="${MAX_NOTES_CHARS:-2800}"

if [[ -z "$RELEASE_TAG" ]]; then
  echo "RELEASE_TAG is required." >&2
  exit 1
fi

if [[ -z "$ARM64_URL" || -z "$X86_64_URL" ]]; then
  echo "ARM64_URL and X86_64_URL are required." >&2
  exit 1
fi

SHORT_VERSION="${RELEASE_TAG#v}"
SHORT_VERSION="${SHORT_VERSION#V}"
BUILD_VERSION="$(tr -cd '0-9' <<<"$SHORT_VERSION")"
if [[ -z "$BUILD_VERSION" ]]; then
  BUILD_VERSION="1"
fi

if [[ -z "$RELEASE_NAME" ]]; then
  RELEASE_NAME="Release ${SHORT_VERSION}"
fi

sanitize_release_notes() {
  local raw="$1"
  local max_chars="$2"
  local cleaned=""

  cleaned="$(printf '%s' "$raw" \
    | tr -d '\r' \
    | sed -E 's/\[([^][]+)\]\(([^()]*)\)/\1/g' \
    | sed -E 's/^#{1,6}[[:space:]]*//g' \
    | sed -E 's/`([^`]*)`/\1/g' \
    | sed -E 's/[*_~]{1,3}//g' \
    | sed -E 's/^[[:space:]]*[-*][[:space:]]+/- /g' \
    | sed -E '/release-notes\.[A-Za-z-]+\.md/d' \
    | sed -E 's/[[:space:]]+$//g')"

  cleaned="$(printf '%s\n' "$cleaned" \
    | awk '
      BEGIN { blank = 0 }
      {
        if ($0 ~ /^[[:space:]]*$/) {
          if (blank == 0) { print ""; blank = 1 }
        } else {
          print $0; blank = 0
        }
      }')"

  if [[ -z "${cleaned//[[:space:]]/}" ]]; then
    cleaned="Bug fixes and improvements."
  fi

  if (( max_chars > 0 )) && (( ${#cleaned} > max_chars )); then
    cleaned="${cleaned:0:max_chars}"
    cleaned="${cleaned%$'\n'*}"
    cleaned="${cleaned% }"
    cleaned="${cleaned}…"
  fi

  printf '%s' "$cleaned"
}

if [[ -z "$ARM64_SIZE" || "$ARM64_SIZE" == "null" ]]; then
  ARM64_SIZE="0"
fi
if [[ -z "$X86_64_SIZE" || "$X86_64_SIZE" == "null" ]]; then
  X86_64_SIZE="0"
fi

if [[ -n "$PUBLISHED_AT" && "$PUBLISHED_AT" != "null" ]]; then
  if PUB_DATE="$(date -u -d "$PUBLISHED_AT" "+%a, %d %b %Y %H:%M:%S +0000" 2>/dev/null)"; then
    :
  elif PUB_DATE="$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$PUBLISHED_AT" "+%a, %d %b %Y %H:%M:%S +0000" 2>/dev/null)"; then
    :
  else
    PUB_DATE="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")"
  fi
else
  PUB_DATE="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")"
fi

mkdir -p "$OUTPUT_DIR"
RELEASE_NOTES_SANITIZED="$(sanitize_release_notes "$RELEASE_NOTES" "$MAX_NOTES_CHARS")"

generate_feed() {
  local arch_label="$1"
  local url="$2"
  local size="$3"
  local out_file="$4"

  cat > "$out_file" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>${APP_NAME} Updates (${arch_label})</title>
    <link>https://github.com/irons163/codex-pool-manager/releases</link>
    <description>Latest ${APP_NAME} updates for ${arch_label}</description>
    <language>en</language>
    <item>
      <title>${RELEASE_NAME}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <description sparkle:format="plain-text"><![CDATA[${RELEASE_NOTES_SANITIZED}]]></description>
      <enclosure
        url="${url}"
        sparkle:version="${BUILD_VERSION}"
        sparkle:shortVersionString="${SHORT_VERSION}"
        type="application/x-apple-diskimage"
        length="${size}" />
    </item>
  </channel>
</rss>
EOF
}

generate_feed "arm64" "$ARM64_URL" "$ARM64_SIZE" "${OUTPUT_DIR}/appcast-arm64.xml"
generate_feed "x86_64" "$X86_64_URL" "$X86_64_SIZE" "${OUTPUT_DIR}/appcast-x86_64.xml"

echo "Generated Sparkle appcasts:"
ls -la "${OUTPUT_DIR}"/appcast-*.xml
