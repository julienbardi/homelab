#!/bin/sh
# secrets-stamp.sh — stamp wrapper for installed secrets-check.sh
set -eu

# Load unified stamp library (pure functions, repo-safe)
. "$(dirname "$0")/stamps.sh"

DIR="$(stamp_init)"
STAMP="$DIR/secrets-check.stamp"

# Compute deterministic repo hash
current_hash="$(stamp_compute_hash)"

# Skip if unchanged
if [ -f "$STAMP" ]; then
    stored="$(cat "$STAMP")"
    if [ "$current_hash" = "$stored" ]; then
        echo "⏩ secrets unchanged — skipping"
        exit 0
    fi
fi

echo "🔍 secrets changed — running scan"

# Always run the installed checker, never the repo version
/usr/local/bin/secrets-check.sh "$@"

# Update stamp
printf '%s\n' "$current_hash" > "$STAMP"
echo "🟢 secrets stamp updated"
