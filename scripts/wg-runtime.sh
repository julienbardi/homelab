#!/usr/bin/env bash
# scripts/wg-runtime.sh
# Authoritative WireGuard runtime status (kernel truth only, intent-scoped)

set -euo pipefail
IFS=$'\n\t'

WG_ROOT="${WG_ROOT:?WG_ROOT must be set}"
PLAN="${PLAN:-$WG_ROOT/compiled/plan.tsv}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

printf '%-6s %-44s %-8s %-22s %-18s %-18s %-30s\n' \
  "Iface" "Peer public key" "Port" "Endpoint" "Last handshake" "RX / TX" "Allowed IPs"
printf '%-6s %-44s %-8s %-22s %-18s %-18s %-30s\n' \
  "------" "--------------------------------------------" "--------" "----------------------" "------------------" "------------------" "------------------------------"

# Interfaces derived from intent (single authoritative accessor)
mapfile -t IFACES < <("$SCRIPT_DIR/wg-plan-ifaces.sh" "$PLAN")

for ifa in "${IFACES[@]}"; do
  # Interface declared but not present in kernel
  if ! ip link show "$ifa" >/dev/null 2>&1; then
	printf '%-6s %-44s %-8s %-22s %-18s %-18s %-30s\n' \
	  "$ifa" "(not present)" "-" "-" "-" "-" "-"
	continue
  fi

  listen="$(wg show "$ifa" listen-port 2>/dev/null || echo "-")"

  # Output format here (as observed):
  # header:  priv  pub  listen  fwmark|off
  # peer:    peer_pub  psk  endpoint  allowed  handshake  rx  tx  keepalive
  wg show "$ifa" dump | tail -n +2 | awk -v IFACE="$ifa" -v PORT="$listen" '
	{
	  pub=$1
	  endpoint=$3
	  allowed=$4
	  handshake=$5
	  rx=$6
	  tx=$7

	  if (endpoint == "" || endpoint == "(none)") endpoint="(none)"
	  if (allowed == "" || allowed == "(none)") allowed="(none)"

	  if (handshake == 0 || handshake == "" || handshake == "(none)") {
		hs="(never)"
	  } else {
		cmd="date -d @" handshake " +\"%Y-%m-%d %H:%M:%S\""
		cmd | getline hs
		close(cmd)
	  }

	  printf "%-6s %-44s %-8s %-22s %-18s %-18s %-30s\n",
		IFACE, pub, PORT, endpoint, hs, rx " / " tx, allowed
	}
  '
done
