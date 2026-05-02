#!/bin/sh
# install_github_binary.sh
# Deterministic GitHub binary installer with optional SHA256 + stamp.
# Usage:
#   install_github_binary.sh URL DEST OWNER GROUP MODE SHA256 STAMP
# Notes:
#   - SHA256: empty string disables checksum enforcement
#   - STAMP:  empty string disables stamp handling

set -eu

URL="$1"
DEST="$2"
OWNER="$3"
GROUP="$4"
MODE="$5"
SHA256_EXPECTED="$6"
STAMP="$7"

INSTALL_URL_FILE_IF_CHANGED="/usr/local/bin/install_url_file_if_changed.sh"

if [ ! -x "$INSTALL_URL_FILE_IF_CHANGED" ]; then
  echo "❌ $INSTALL_URL_FILE_IF_CHANGED not executable" >&2
  exit 1
fi

# Fast-path: if stamp + binary exist and SHA matches (when provided), skip.
if [ -n "$STAMP" ] && [ -f "$STAMP" ] && [ -x "$DEST" ]; then
  if [ -n "$SHA256_EXPECTED" ]; then
	CURRENT_SHA=$(/usr/bin/sha256sum "$DEST" | awk '{print $1}')
	if [ "$CURRENT_SHA" = "$SHA256_EXPECTED" ]; then
	  echo "⏩ fast-path: binary already installed (hash match, stamp present)"
	  exit 0
	fi
  else
	echo "⏩ fast-path: binary already installed (stamp + executable present)"
	exit 0
  fi
fi

RC=0
if "$INSTALL_URL_FILE_IF_CHANGED" "$URL" "$DEST" "$OWNER" "$GROUP" "$MODE" "$SHA256_EXPECTED"; then
  RC=0
else
  RC=$?
fi

if [ "$RC" -ne 0 ] && [ "$RC" -ne 3 ]; then
  echo "❌ install_url_file_if_changed.sh failed with exit $RC" >&2
  exit "$RC"
fi

if [ -n "$STAMP" ]; then
  TMP_STAMP="${STAMP}.tmp"
  printf '%s\n' "$URL" > "$TMP_STAMP"
  mv "$TMP_STAMP" "$STAMP"
fi

if [ "$RC" -eq 3 ]; then
  echo "✅ binary installed/updated from $URL"
else
  echo "ℹ️ binary already up-to-date from $URL"
fi
