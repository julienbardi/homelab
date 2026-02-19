#!/usr/bin/env bash
# scripts/wg-plan-read.sh
# Canonical reader for compiled plan.tsv

set -euo pipefail
: "${WG_ROOT:?WG_ROOT not set}"

PLAN="$WG_ROOT/compiled/plan.tsv"

[ -f "$PLAN" ] || {
	echo "wg-plan-read: ERROR: missing plan.tsv" >&2
	exit 2
}

awk -F'\t' '
	BEGIN {
		OFS="\t"
	}

	/^#/ || /^[[:space:]]*$/ { next }

	!seen {
		seen=1
		if ($1!="base" ||
			$2!="iface" ||
			$3!="slot" ||
			$4!="dns" ||
			$5!="client_addr4" ||
			$6!="client_addr6" ||
			$7!="AllowedIPs_client" ||
			$8!="AllowedIPs_server" ||
			$9!="endpoint" ||
			$10!="server_addr4" ||
			$11!="server_addr6" ||
			$12!="server_routes") {
			exit 1
		}
		next
	}

	{
		if (NF != 12) { exit 1 }
		print
	}
' "$PLAN" || {
	echo "wg-plan-read: ERROR: plan.tsv header mismatch" >&2
	exit 2
}
