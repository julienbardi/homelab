#!/usr/bin/env bash
# wg-summary.sh
set -euo pipefail

echo "WireGuard status summary:"
printf "%-6s %-44s %-6s %-10s %-10s\n" \
	"IFACE" "PEER_PUBLIC_KEY" "PORT" "RX" "TX"
printf "%-6s %-44s %-6s %-10s %-10s\n" \
	"------" "--------------------------------------------" "------" "----------" "----------"

wg show all dump | awk '
$1 == "interface" {
	iface = $2
	port  = $5
	next
}
$1 == "peer" {
	printf "%-6s %-44s %-6s %-10s %-10s\n",
		iface, $2, port, $7, $8
}
'
