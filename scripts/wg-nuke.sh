#!/usr/bin/env bash
set -euo pipefail

WG_DIR="/etc/wireguard"

echo "Stopping deployed WireGuard interfaces"
for conf in "$WG_DIR"/*.conf; do
	[ -f "$conf" ] || continue
	iface="$(basename "$conf" .conf)"
	wg-quick down "$iface" 2>/dev/null || true
done

echo "Removing deployed WireGuard configs and keys"
rm -f "$WG_DIR"/*.conf
rm -f "$WG_DIR"/*.key
rm -f "$WG_DIR"/*.pub

echo "Deployment state removed"
