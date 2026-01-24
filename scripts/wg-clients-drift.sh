#!/bin/sh
# wg-clients-drift.sh
set -eu
: "${WG_ROOT:?WG_ROOT not set}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Render clients into temp output
export WG_OUT="$TMP"
./scripts/wg-compile-clients.sh >/dev/null

REAL="$WG_ROOT/export/clients"
TEST="$TMP/clients"

# No existing output → drift
if [ ! -d "$REAL" ]; then
    echo "⚠️  Client output directory missing: $REAL" >&2
    exit 1
fi

# Compare
if diff -qr "$REAL" "$TEST" >/dev/null; then
    exit 0
fi

echo "❌ Client config drift detected:" >&2
echo >&2

# Show which files differ
diff -qr "$REAL" "$TEST" | sed 's/^/  • /' >&2
echo >&2

# Show unified diffs (safe, readable)
for f in $(diff -qr "$REAL" "$TEST" | awk '/Files/ {print $2}'); do
    rel="${f#"$REAL"/}"
    echo "─── diff: $rel ───" >&2
    diff -u "$REAL/$rel" "$TEST/$rel" >&2 || true
    echo >&2
done

exit 1
