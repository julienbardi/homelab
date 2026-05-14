#!/bin/sh
set -eu

. ./scripts/stamps.sh

DIR="$(stamp_init)"
STAMP="$DIR/gitignore-check.stamp"

# Compute per-invariant hash (only the 3 relevant files)
current_hash="$(stamp_compute_hash_gitignore)"

# Check if stamp exists and matches
if [ -f "$STAMP" ]; then
    stored_hash="$(cat "$STAMP")"
    if [ "$current_hash" = "$stored_hash" ]; then
        echo "⏩ gitignore unchanged — skipping"
        exit 0
    fi
fi

echo "🔍 gitignore changed — running check"
./scripts/gitignore-check.sh

# Update stamp
printf '%s\n' "$current_hash" > "$STAMP"
echo "🆗 gitignore stamp updated"
