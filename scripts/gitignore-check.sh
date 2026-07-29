#!/bin/sh
# ============================================================
# gitignore-check.sh — Validate .gitignore invariants (runtime)
# ============================================================

set -eu

SCRIPT_DIR="$(dirname "$0")"

# Load shared stamp primitives
. "$SCRIPT_DIR/stamps.sh"

# ------------------------------------------------------------
# Resolve authoritative .gitignore via stamps.sh
# ------------------------------------------------------------
# stamps.sh already provides a safe way to access git-tracked files.
# We use stamp_git_filelist to locate .gitignore without REPO_ROOT.
# ------------------------------------------------------------

if [ -z "${REPO_ROOT:-}" ]; then
	echo "❌ REPO_ROOT not set — cannot validate .gitignore"
	exit 1
fi

GITIGNORE="$REPO_ROOT/.gitignore"

if [ ! -f "$GITIGNORE" ]; then
	echo "❌ .gitignore not found at $GITIGNORE"
	exit 1
fi

# ------------------------------------------------------------
# Forbidden patterns (runtime-safe)
# ------------------------------------------------------------
# These patterns must NOT appear in .gitignore.
# They hide secrets or LAN IPs and break repo-preflight.
# ------------------------------------------------------------

forbidden_patterns="
192.168.
10.0.
password
passwd
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
