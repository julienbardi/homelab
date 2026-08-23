#!/bin/sh
# install_github_asset.sh URL DEST SHA256 STAMP TOOL_LABEL
# -----------------------------------------------------------------------------
# Safe, idempotent, and deterministic GitHub asset downloader and installer.
# BusyBox-compatible, preserves strict permission and argument contracts.
# -----------------------------------------------------------------------------
set -eu

URL="$1"
DEST="$2"
SHA256_EXPECTED="$3"
SHA256_EXPECTED="${SHA256_EXPECTED#sha256:}"
STAMP="$4"
TOOL_LABEL="${5:-$(basename "$DEST")}"

BASENAME="$(basename "$DEST")"

# Ensure target system directories exist cleanly
mkdir -p "$(dirname "$DEST")"
mkdir -p "$(dirname "$STAMP")"

TMP_ASSET=""
WORK=""
LIST_FILE=""
TMP_DEST=""

cleanup() {
    set +e
    [ -n "$TMP_ASSET" ] && [ -f "$TMP_ASSET" ] && rm -f "$TMP_ASSET" || true
    [ -n "$LIST_FILE" ] && [ -f "$LIST_FILE" ] && rm -f "$LIST_FILE" || true
    [ -n "$TMP_DEST" ] && [ -f "$TMP_DEST" ] && rm -f "$TMP_DEST" || true
    [ -n "$WORK" ] && [ -d "$WORK" ] && rm -rf "$WORK" || true
}
trap cleanup EXIT

# ------------------------------------------------------------
# Download asset securely to transient file (WAN execution)
# ------------------------------------------------------------
TMP_ASSET="$(mktemp 2>/dev/null || mktemp -t 'asset')"
curl -fsSL \
    --connect-timeout 5 \
    --max-time 30 \
    --retry 3 \
    --retry-delay 1 \
    "$URL" -o "$TMP_ASSET"

# ------------------------------------------------------------
# Verify SHA256 integrity of the downloaded payload
# ------------------------------------------------------------
ACTUAL="$(sha256sum "$TMP_ASSET" | awk '{print $1}')"
if [ "$ACTUAL" != "$SHA256_EXPECTED" ]; then
    echo "ERROR: sha256 mismatch" >&2
    echo "  expected: $SHA256_EXPECTED" >&2
    echo "  actual:   $ACTUAL" >&2
    exit 1
fi

# ------------------------------------------------------------
# Detect asset container type
# ------------------------------------------------------------
case "$URL" in
    *.tar.gz|*.tgz) TYPE="tar" ;;
    *.zip)          TYPE="zip" ;;
    *.deb)          TYPE="deb" ;;
    *)              TYPE="raw" ;;
esac

# ------------------------------------------------------------
# Handle raw binary installation directly via atomic transaction
# ------------------------------------------------------------
if [ "$TYPE" = "raw" ]; then
    TMP_DEST="$(mktemp "$(dirname "$DEST")/tmp.XXXXXX" 2>/dev/null || mktemp -t 'dest')"
    install -m 0755 "$TMP_ASSET" "$TMP_DEST"
    mv -f "$TMP_DEST" "$DEST"
    echo "🚀 Installed raw binary: $DEST"
    exit 0
fi

# ------------------------------------------------------------
# Extract archive into isolated temporary workspace
# ------------------------------------------------------------
WORK="$(mktemp -d 2>/dev/null || mktemp -d -t 'work')"

if [ "$TYPE" = "tar" ]; then
    tar -xzf "$TMP_ASSET" -C "$WORK"
elif [ "$TYPE" = "zip" ]; then
    unzip -q "$TMP_ASSET" -d "$WORK"
elif [ "$TYPE" = "deb" ]; then
    dpkg-deb -x "$TMP_ASSET" "$WORK" >/dev/null
fi

# ------------------------------------------------------------
# Strict binary discovery
# ------------------------------------------------------------
MATCHES=""
COUNT=0
LIST_FILE="$(mktemp 2>/dev/null || mktemp -t 'list')"

find "$WORK" -type f -name "$BASENAME" 2>/dev/null > "$LIST_FILE"

while IFS= read -r FILE; do
    [ -z "$FILE" ] && continue
    case "$FILE" in
        *__MACOSX*|*/.*) continue ;;
    esac
    MATCHES="$FILE"
    COUNT=$((COUNT + 1))
done < "$LIST_FILE"

if [ "$COUNT" -eq 0 ]; then
    echo "ERROR: no file named '$BASENAME' found in asset" >&2
    exit 1
fi

if [ "$COUNT" -gt 1 ]; then
    echo "ERROR: multiple entries named '$BASENAME' found in asset" >&2
    exit 1
fi

# ------------------------------------------------------------
# Install discovered binary safely via transactional move
# ------------------------------------------------------------
TMP_DEST="$(mktemp "$(dirname "$DEST")/tmp.XXXXXX" 2>/dev/null \
    || mktemp -p "$(dirname "$DEST")" tmp.XXXXXX)"

install -m 0755 "$MATCHES" "$TMP_DEST"
mv -f "$TMP_DEST" "$DEST"

echo "🚀 Installed/updated $DEST"