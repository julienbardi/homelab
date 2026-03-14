#!/bin/sh
set -eu
LC_ALL=C; export LC_ALL

URL="$1"
DST="$2"
OWNER="$3"
GROUP="$4"
MODE="$5"

[ -n "$URL" ] && [ -n "$DST" ] && [ -n "$OWNER" ] && [ -n "$GROUP" ] && [ -n "$MODE" ] || {
    echo "Usage: URL DST_PATH OWNER GROUP MODE" >&2
    exit 1
}

TMP="${TMPDIR:-/tmp}/.ifc_url.$$"

trap 'rm -f "$TMP"' EXIT

curl -fsSL "$URL" -o "$TMP"

SRC_HASH="$(sha256sum "$TMP" | awk '{print $1}')"
DST_HASH="$(sha256sum "$DST" 2>/dev/null | awk '{print $1}' || true)"

[ "$SRC_HASH" = "$DST_HASH" ] && exit 0

sudo sh -c "
    mv -f '$TMP' '$DST'
    chown '$OWNER:$GROUP' '$DST' 2>/dev/null || chown '$OWNER' '$DST'
    chmod '$MODE' '$DST'
    sync
"

exit 3
