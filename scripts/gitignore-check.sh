#!/bin/sh
# ============================================================
# gitignore-check.sh — Validate .gitignore invariants (runtime)
#
# DEPENDS:
#   - stamps.sh
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

# ------------------------------------------------------------
# Validate .gitignore contents
# ------------------------------------------------------------
# BusyBox-safe: no arrays, no bashisms
# We assume the authoritative .gitignore is the one in the repo root,
# but runtime scripts cannot reference repo paths directly.
#
# Therefore, the Makefile MUST export REPO_ROOT before calling this script.
# This is already true in your homelab architecture.
# ------------------------------------------------------------

if [ -z "${REPO_ROOT:-}" ]; then
    echo "❌ REPO_ROOT not set — cannot validate .gitignore"
    echo "   Makefile must export REPO_ROOT before calling gitignore-check.sh"
    exit 1
fi

GITIGNORE="$REPO_ROOT/.gitignore"

if [ ! -f "$GITIGNORE" ]; then
    echo "❌ .gitignore not found at $GITIGNORE"
    exit 1
fi

# ------------------------------------------------------------
# Actual validation logic
# ------------------------------------------------------------
# Example invariant:
#   - No LAN IPs should appear in .gitignore
#   - No secrets patterns should appear
#   - No forbidden patterns should appear
#
# You can extend this as needed.
# ------------------------------------------------------------

forbidden_patterns="
192.168.
10.0.
secret
password
"

violations=0

for pattern in $forbidden_patterns; do
    if grep -q "$pattern" "$GITIGNORE"; then
        echo "❌ Forbidden pattern in .gitignore: $pattern"
        violations=1
    fi
done

if [ "$violations" -ne 0 ]; then
    echo "❌ .gitignore validation FAILED"
    exit 1
fi

echo "🟢 .gitignore validation OK"
