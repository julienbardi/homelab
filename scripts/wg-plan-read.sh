#!/usr/bin/env bash
# scripts/wg-plan-read.sh
# Canonical reader for compiled plan.tsv (schema v2)

set -euo pipefail

PLAN="${1:?usage: wg-plan-read.sh /path/to/plan.tsv}"

[ -f "$PLAN" ] || {
	echo "wg-plan-read: ERROR: missing plan.tsv: $PLAN" >&2
	exit 2
}

awk -F'\t' '
	BEGIN {
		OFS = "\t"
		header_seen = 0
		schema_ok = 0
	}

	/^[[:space:]]*$/ { next }

	/^#/ {
		if ($0 == "# plan.tsv schema: v2") {
			schema_ok = 1
		}
		next
	}

	!header_seen {
		header_seen = 1

		if (!schema_ok) {
			exit 10
		}

		if ($1!="node" || $2!="iface" || $3!="profile" || $4!="tunnel_mode" || \
			$5!="lan_access" || $6!="egress_v4" || $7!="egress_v6" || \
			$8!="client_addr_v4" || $9!="client_addr_v6" || \
			$10!="client_allowed_ips_v4" || $11!="client_allowed_ips_v6" || \
			$12!="server_allowed_ips_v4" || $13!="server_allowed_ips_v6" || \
			$14!="dns" || NF!=14) {
			exit 11
		}
		next
	}

	{
		if (NF != 14) {
			exit 12
		}
		print
	}
' "$PLAN"
rc=$?

case "$rc" in
	0) exit 0 ;;
	10) echo "wg-plan-read: ERROR: missing schema marker (# plan.tsv schema: v2)" >&2 ;;
	11) echo "wg-plan-read: ERROR: header mismatch" >&2 ;;
	12) echo "wg-plan-read: ERROR: data row field count != 14" >&2 ;;
	*)  echo "wg-plan-read: ERROR: awk failed (rc=$rc)" >&2 ;;
esac
exit 2

