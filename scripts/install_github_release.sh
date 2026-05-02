#!/bin/sh
# install_github_release.sh
set -eu

TYPE="$1"
URL="$2"
DEST="$3"
SHA256_EXPECTED="$4"
STAMP="$5"

# Ensure directories exist
DESTDIR="$(dirname "$DEST")"
mkdir -p "$DESTDIR"
mkdir -p "$(dirname "$STAMP")"

# ------------------------------------------------------------
# Fast-path: stamp + binary + SHA match
# ------------------------------------------------------------
if [ -f "$STAMP" ] && [ -x "$DEST" ]; then
    if grep -qx "$SHA256_EXPECTED" "$STAMP" 2>/dev/null; then
        echo "⏩ $(basename "$DEST") (fast-path: hash+stamp OK)"
        exit 0
    fi
fi

# ------------------------------------------------------------
# Download asset
# ------------------------------------------------------------
TMP_ASSET="$(mktemp)"
curl -fsSL "$URL" -o "$TMP_ASSET"

# ------------------------------------------------------------
# Verify SHA256 if provided
# ------------------------------------------------------------
if [ -n "$SHA256_EXPECTED" ]; then
    ACTUAL_SHA="$(sha256sum "$TMP_ASSET" | awk '{print $1}')"
    if [ "$ACTUAL_SHA" != "$SHA256_EXPECTED" ]; then
        echo "❌ SHA256 mismatch"
        echo "expected: $SHA256_EXPECTED"
        echo "actual:   $ACTUAL_SHA"
        rm -f "$TMP_ASSET"
        exit 1
    fi
fi

# ------------------------------------------------------------
# Install based on TYPE
# ------------------------------------------------------------
case "$TYPE" in
    single)
        chmod 0755 "$TMP_ASSET"
        mv "$TMP_ASSET" "$DEST"
        ;;

    tar)
        TMPDIR="$(mktemp -d)"
        tar -C "$TMPDIR" -xzf "$TMP_ASSET"
        BIN="$(find "$TMPDIR" -type f -maxdepth 1 | head -n1)"
        chmod 0755 "$BIN"
        mv "$BIN" "$DEST"
        rm -rf "$TMPDIR"
        rm -f "$TMP_ASSET"
        ;;

    deb)
        dpkg -i "$TMP_ASSET"
        rm -f "$TMP_ASSET"
        ;;

    *)
        echo "❌ Unknown TYPE: $TYPE"
        rm -f "$TMP_ASSET"
        exit 1
        ;;
esac

# ------------------------------------------------------------
# Write stamp
# ------------------------------------------------------------
echo "$SHA256_EXPECTED" > "$STAMP"

echo "✅ Installed from $URL"
