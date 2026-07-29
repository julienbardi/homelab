#!/bin/sh
# ============================================================
# secrets-stamp.sh — Secret material invariant stamp (runtime)
#
# DEPENDS:
#   - stamps.sh
#   - secrets-check.sh
#
# CONTRACT:
# - This script is installed into /usr/local/bin by `make install-all`.
# - It MUST NOT reference repo paths (./scripts/... or $REPO_ROOT/...).
# - It MUST reference sibling installed scripts via $SCRIPT_DIR.
# - All dependent scripts MUST be installed into the same directory.
# - Repo-preflight executes this script directly.
# - Repo scripts are source-only and must never be executed.
# - BusyBox-safe: no arrays, no bashisms.
# ============================================================

set -eu

SCRIPT_DIR="$(dirname "$0")"

# Load shared stamp primitives
. "$SCRIPT_DIR/stamps.sh"

DIR="$(stamp_init)"
STAMP="$DIR/secrets-check.stamp"

# ------------------------------------------------------------
# Compute per-invariant hash for secrets
# ------------------------------------------------------------
stamp_compute_hash_secrets() {
    # Hash only the files relevant to the secrets invariant
    # BusyBox-safe: explicit file list, no arrays
    sha256sum \
        "$SCRIPT_DIR/secrets-check.sh" \
        "$SCRIPT_DIR/secrets-stamp.sh" \
    | sha256sum | awk '{print $1}'
}

current_hash="$(stamp_compute_hash_secrets)"

# ------------------------------------------------------------
# Check if stamp exists and matches
# ------------------------------------------------------------
if [ -f "$STAMP" ]; then
    stored_hash="$(cat "$STAMP")"
    if [ "$current_hash" = "$stored_hash" ]; then
        echo "⏩ secrets unchanged — skipping"
        exit 0
    fi
fi

echo "🔍 secrets changed — running scan"

# ------------------------------------------------------------
# Run installed secrets-check.sh
# ------------------------------------------------------------
"$SCRIPT_DIR/secrets-check.sh"

# ------------------------------------------------------------
# Update stamp
# ------------------------------------------------------------
printf '%s\n' "$current_hash" > "$STAMP"
echo "🟢 secrets stamp updated"
