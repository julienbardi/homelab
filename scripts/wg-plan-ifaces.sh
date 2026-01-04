#!/usr/bin/env bash
# scripts/wg-plan-ifaces.sh
# Canonical WireGuard intent accessor: emit active ifaces from plan.tsv

set -euo pipefail

PLAN="$1"
[ -f "$PLAN" ] || { echo "wg-plan-ifaces: ERROR: missing plan: $PLAN" >&2; exit 2; }

# --------------------------------------------------------------------
# Strict header validation (identical to wg-deploy)
# --------------------------------------------------------------------
awk -F'\t' '
	/^#/ { next }
	/^[[:space:]]*$/ { next }
	!seen {
		seen=1
		if ($1=="base" &&
			$2=="iface" &&
			$3=="slot" &&
			$4=="dns" &&
			$5=="client_addr4" &&
			$6=="client_addr6" &&
			$7=="AllowedIPs_client" &&
			$8=="AllowedIPs_server" &&
			$9=="endpoint") exit 0
		exit 1
	}
' "$PLAN" || {
	echo "wg-plan-ifaces: ERROR: plan.tsv header does not match strict contract" >&2
	exit 2
}

# --------------------------------------------------------------------
# Emit unique, non-empty iface names (column 2)
# --------------------------------------------------------------------
awk -F'\t' '
	/^#/ { next }
	/^[[:space:]]*$/ { next }

	# Skip header row
	$1=="base" &&
	$2=="iface" &&
	$3=="slot" &&
	$4=="dns" &&
	$5=="client_addr4" &&
	$6=="client_addr6" &&
	$7=="AllowedIPs_client" &&
	$8=="AllowedIPs_server" &&
	$9=="endpoint" { next }

	$2 != "" { print $2 }
' "$PLAN" | sort -u
