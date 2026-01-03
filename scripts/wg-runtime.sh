#!/usr/bin/env bash
# scripts/wg-runtime.sh
# Authoritative WireGuard runtime status (kernel truth only)

set -euo pipefail
IFS=$'\n\t'

printf '%-6s %-44s %-8s %-22s %-18s %-18s %-30s\n' \
  "Iface" "Peer public key" "Port" "Endpoint" "Last handshake" "RX / TX" "Allowed IPs"
printf '%-6s %-44s %-8s %-22s %-18s %-18s %-30s\n' \
  "------" "--------------------------------------------" "--------" "----------------------" "------------------" "------------------" "------------------------------"

mapfile -t IFACES < <(ip -o link show type wireguard 2>/dev/null | awk -F': ' '{print $2}')

for ifa in "${IFACES[@]}"; do
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
