#!/bin/sh
set -eu
# gitignore-stamp.sh
# Depends on:
# - stamps.sh
# - gitignore-check.stamp
# - gitignore-check.sh
# CONTRACT:
# - This script is installed into /usr/local/bin by `make install-all`.
# - It MUST NOT reference repo paths (./scripts/...).
# - It MUST reference sibling installed scripts via $SCRIPT_DIR.
# - Dependencies:
#     - stamps.sh
#     - gitignore-check.sh
# - All dependent scripts MUST be installed into the same directory.
# - Repo-preflight executes this script directly.
# - Repo scripts are source-only and must never be executed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load shared stamp primitives
COMMON="$SCRIPT_DIR/stamps.sh"
[[ -f "$COMMON" ]] || { echo "❌ Error: $COMMON not found" >&2; exit 1; }
source "$COMMON"

DIR="$(stamp_init)"
STAMP="$DIR/gitignore-check.stamp"

current_hash="$(stamp_compute_hash_gitignore)"

if [ -f "$STAMP" ]; then
	stored_hash="$(cat "$STAMP")"
	if [ "$current_hash" = "$stored_hash" ]; then
		echo "⏩ gitignore unchanged — skipping"
		exit 0
	fi
fi

echo "🔍 gitignore changed — running check"

# Use installed gitignore-check.sh
"$SCRIPT_DIR/gitignore-check.sh"

printf '%s\n' "$current_hash" > "$STAMP"
echo "🟢 gitignore stamp updated"
