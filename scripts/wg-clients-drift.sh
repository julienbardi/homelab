#!/bin/sh
# wg-clients-drift.sh
# CONTRACT:
# - Read-only inspection
# - Requires WG_ROOT
# - Does not modify runtime state
# - Exit 0 = clean, 1 = drift
set -eu
: "${WG_ROOT:?WG_ROOT not set}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Render clients into temp output
export WG_OUT="$TMP"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/wg-compile-clients.sh" >/dev/null

REAL="$WG_ROOT/export/clients"
TEST="$TMP/clients"

# No existing output -> drift
if [ ! -d "$REAL" ]; then
    echo "❌ Client output directory missing: $REAL" >&2
    exit 1
fi

# Compare
DIFF="$(diff -qr "$REAL" "$TEST" || true)"

[ -z "$DIFF" ] && exit 0

echo "❌ Client config drift detected:" >&2
echo >&2

printf '%s\n' "$DIFF" | sed 's/^/  • /' >&2
echo >&2

printf '%s\n' "$DIFF" | awk '/Files/ {print $2}' | while IFS= read -r f; do
    rel="${f#"$REAL"/}"
    echo "——— diff: $rel ———" >&2
    diff -u "$REAL/$rel" "$TEST/$rel" >&2 || true
    echo >&2
done

exit 1
