#!/bin/sh
# install_github_tarball.sh URL DEST_BINARY INNER_NAME SHA256 STAMP

set -eu

URL="$1"
DEST="$2"
INNER="$3"
SHA256_EXPECTED="$4"
STAMP="$5"

TMP="$(mktemp)"
curl -fsSL "$URL" -o "$TMP"

if [ -n "$SHA256_EXPECTED" ]; then
    ACTUAL="$(sha256sum "$TMP" | awk '{print $1}')"
    if [ "$ACTUAL" != "$SHA256_EXPECTED" ]; then
        echo "ERROR: sha256 mismatch"
        echo "  expected: $SHA256_EXPECTED"
        echo "  actual:   $ACTUAL"
        exit 1
    fi
fi

WORK="$(mktemp -d)"
tar -xzf "$TMP" -C "$WORK"

BIN="$WORK/$INNER"
if [ ! -f "$BIN" ]; then
    echo "ERROR: inner binary '$INNER' not found in tarball"
    exit 1
fi

install -m 0755 "$BIN" "$DEST"

echo "version=$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STAMP"

rm -rf "$TMP" "$WORK"

echo "⏩ installed/updated $DEST"
