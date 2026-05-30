#!/bin/sh
# common.sh — shell platform contract

# -----------------------------------------------------------------------------
# Help when executed directly
# -----------------------------------------------------------------------------

if [ "${0##*/}" = "common.sh" ]; then
	cat <<'EOF'
common.sh — shell platform contract

This file defines the minimum shell platform guarantees required by
router control-plane scripts.

It MUST be sourced by all scripts.

Guaranteed after sourcing:
  - GNU awk at /jffs/scripts/bin/awk
  - BusyBox-safe: sort, sed, printf, rm, mv, mkdir
  - mktemp or safe fallback
  - RANDOM detection
  - Temporary file helper

This file produces no output when sourced.
EOF
	exit 0
fi

# -----------------------------------------------------------------------------
# Strict shell baseline
# -----------------------------------------------------------------------------

set -eu
umask 077

PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH

LC_ALL=C
export LC_ALL

# -----------------------------------------------------------------------------
# Command detection helpers
# -----------------------------------------------------------------------------

have_cmd() {
	type "$1" >/dev/null 2>&1
}

require_cmd() {
	have_cmd "$1" || {
		echo "❌ Missing required platform command: $1" >&2
		exit 1
	}
}

# -----------------------------------------------------------------------------
# Platform command guarantees
# -----------------------------------------------------------------------------

# GNU awk is required (BusyBox awk is insufficient)
AWK="/jffs/scripts/bin/awk"
require_cmd "$AWK"
export AWK

# BusyBox-safe core utilities
require_cmd sort
require_cmd sed
require_cmd printf
require_cmd rm
require_cmd mv
require_cmd mkdir

# -----------------------------------------------------------------------------
# Capability probes
# -----------------------------------------------------------------------------

if have_cmd mktemp; then
	HAVE_MKTEMP=1
else
	HAVE_MKTEMP=0
fi

if [ -n "${RANDOM+x}" ]; then
	HAVE_RANDOM=1
else
	HAVE_RANDOM=0
fi

# -----------------------------------------------------------------------------
# Temporary file helper
# -----------------------------------------------------------------------------

make_tmp() {
	prefix=$1

	if [ "$HAVE_MKTEMP" -eq 1 ]; then
		mktemp "/tmp/${prefix}.XXXXXX"
	elif [ "$HAVE_RANDOM" -eq 1 ]; then
		printf '/tmp/%s.%s.%s\n' "$prefix" "$$" "$RANDOM"
	else
		printf '/tmp/%s.%s\n' "$prefix" "$$"
	fi
}
