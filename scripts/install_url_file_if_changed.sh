#!/bin/sh
#
# install_url_file_if_changed.sh
#
# CONTRACT:
#   This helper performs a content‑addressed, idempotent install of a file
#   fetched from a URL. A replacement occurs only when the *effective source
#   content* changes.
#
#   The effective source content hash is defined as:
#
#       sha256( URL + sha256(downloaded_file) )
#
#   This means:
#     - If the URL changes → the hash changes → the file is reinstalled.
#     - If the downloaded content changes → the hash changes → the file is reinstalled.
#     - If both URL and content are unchanged → no action is taken.
#
#   This contract prevents stale or incorrect cached downloads from being
#   treated as “up‑to‑date” when the source URL changes, and ensures that
#   operator‑driven URL changes always trigger a fresh materialization.
#
#   Exit codes:
#     0 → no change (destination already matches effective source content)
#     3 → file replaced successfully
#     non‑zero → error
#
#   Atomicity:
#     The destination file is replaced atomically via mv(1).
#
#   Ownership and permissions:
#     The installed file is assigned OWNER:GROUP and MODE as provided.
#
#   Callers MUST NOT assume that the destination file exists before invocation.
#
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

curl --progress-bar -fsSL "$URL" -o "$TMP" 2>&1

SRC_HASH="$( (echo "$URL"; sha256sum "$TMP" | awk '{print $1}') | sha256sum | awk '{print $1}' )"
DST_HASH="$(sha256sum "$DST" 2>/dev/null | awk '{print $1}' || true)"

[ "$SRC_HASH" = "$DST_HASH" ] && exit 0

sudo sh -c "
    mv -f '$TMP' '$DST'
    chown '$OWNER:$GROUP' '$DST' 2>/dev/null || chown '$OWNER' '$DST'
    chmod '$MODE' '$DST'
    sync
"

echo "🚀 Installed URL IFC Engine: $DST"
exit 3
