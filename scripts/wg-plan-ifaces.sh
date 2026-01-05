#!/usr/bin/env bash
# scripts/wg-plan-ifaces.sh
# Emit unique WireGuard interface names from canonical plan reader

set -euo pipefail

: "${WG_ROOT:?WG_ROOT not set}"

PLAN_READER="$(dirname "$0")/wg-plan-read.sh"

[ -x "$PLAN_READER" ] || {
	echo "wg-plan-ifaces: ERROR: missing plan reader: $PLAN_READER" >&2
	exit 2
}

# --------------------------------------------------------------------
# Emit unique, non-empty iface names (column 2)
# --------------------------------------------------------------------
"$PLAN_READER" | awk -F'\t' '
	$2 != "" { print $2 }
' | sort -u
