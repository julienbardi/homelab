#!/bin/sh
set -eu

. ./scripts/stamps.sh

DIR="$(stamp_init)"
STAMP="$DIR/secrets-check.stamp"

# Compute full-repo hash (safest possible rule)
current_hash="$(stamp_compute_hash)"

# Check if stamp exists and matches
if [ -f "$STAMP" ]; then
    stored_hash="$(cat "$STAMP")"
    if [ "$current_hash" = "$stored_hash" ]; then
        echo "⏩ secrets unchanged — skipping"
        exit 0
    fi
fi

echo "🔍 secrets changed — running scan"
./scripts/secrets-check.sh

# Update stamp
printf '%s\n' "$current_hash" > "$STAMP"
echo "🆗 secrets stamp updated"
