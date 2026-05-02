#!/bin/sh
# install_github_asset.sh URL DEST SHA256 STAMP TOOL_LABEL
set -eu

URL="$1"
DEST="$2"
SHA256_EXPECTED="$3"
STAMP="$4"
TOOL_LABEL="${5:-$(basename "$DEST")}"

BASENAME="$(basename "$DEST")"

# Ensure directories exist
mkdir -p "$(dirname "$DEST")"
mkdir -p "$(dirname "$STAMP")"

# ------------------------------------------------------------
# Fast-path skip: stamp + dest + hash match
# ------------------------------------------------------------
if [ -f "$STAMP" ] && [ -x "$DEST" ]; then
    CURRENT="$(sha256sum "$DEST" | awk '{print $1}')"
    if [ "$CURRENT" = "$SHA256_EXPECTED" ]; then
        echo "⏩ ${TOOL_LABEL} (fast-path: hash+stamp OK): $CURRENT"
        exit 0
    fi
fi

# ------------------------------------------------------------
# Download asset
# ------------------------------------------------------------
TMP_ASSET="$(mktemp)"
curl -fsSL "$URL" -o "$TMP_ASSET"

# ------------------------------------------------------------
# Verify SHA256
# ------------------------------------------------------------
ACTUAL="$(sha256sum "$TMP_ASSET" | awk '{print $1}')"
if [ "$ACTUAL" != "$SHA256_EXPECTED" ]; then
    echo "ERROR: sha256 mismatch"
    echo "  expected: $SHA256_EXPECTED"
    echo "  actual:   $ACTUAL"
    exit 1
fi

# ------------------------------------------------------------
# Detect asset type
# ------------------------------------------------------------
case "$URL" in
    *.tar.gz|*.tgz) TYPE="tar" ;;
    *.zip)          TYPE="zip" ;;
    *.deb)          TYPE="deb" ;;
    *)              TYPE="raw" ;;
esac

# ------------------------------------------------------------
# Handle raw binary
# ------------------------------------------------------------
if [ "$TYPE" = "raw" ]; then
    install -m 0755 "$TMP_ASSET" "$DEST"
    echo "$SHA256_EXPECTED" > "$STAMP"
    echo "🚀 Installed raw binary: $DEST"
    exit 0
fi

# ------------------------------------------------------------
# Extract archive
# ------------------------------------------------------------
WORK="$(mktemp -d)"

if [ "$TYPE" = "tar" ]; then
    tar -xzf "$TMP_ASSET" -C "$WORK"
elif [ "$TYPE" = "zip" ]; then
    unzip -q "$TMP_ASSET" -d "$WORK"
elif [ "$TYPE" = "deb" ]; then
    dpkg-deb -x "$TMP_ASSET" "$WORK"
fi

# ------------------------------------------------------------
# Strict binary discovery
# ------------------------------------------------------------
MATCHES="$(find "$WORK" -type f -name "$BASENAME" -perm -111)"
COUNT="$(printf "%s" "$MATCHES" | grep -c '^' || true)"

if [ "$COUNT" -eq 0 ]; then
    echo "ERROR: no executable named '$BASENAME' found in asset"
    exit 1
fi

if [ "$COUNT" -gt 1 ]; then
    echo "ERROR: multiple executables named '$BASENAME' found:"
    echo "$MATCHES"
    exit 1
fi

# ------------------------------------------------------------
# Install the discovered binary
# ------------------------------------------------------------
install -m 0755 "$MATCHES" "$DEST"

# ------------------------------------------------------------
# Write stamp
# ------------------------------------------------------------
echo "$SHA256_EXPECTED" > "$STAMP"

# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------
rm -rf "$TMP_ASSET" "$WORK"

echo "🚀 Installed/updated $DEST"
