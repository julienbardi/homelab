#!/usr/bin/env bash
set -euo pipefail

echo "Stopping all WireGuard interfaces"
for iface in /etc/wireguard/wg*.conf; do
	[ -e "$iface" ] || continue
	wg-quick down "$(basename "$iface" .conf)" || true
done

echo "Removing server configs and keys"
rm -f /etc/wireguard/wg*.conf
rm -f /etc/wireguard/wg*.key
rm -f /etc/wireguard/wg*.pub

echo "Removing compiled artifacts"
rm -rf out/server
rm -rf out/clients

echo "Regenerating server keys"
for iface in wg0 wg1 wg2 wg3 wg4 wg5 wg6 wg7; do
	wg genkey | tee "/etc/wireguard/${iface}.key" | wg pubkey > "/etc/wireguard/${iface}.pub"
done

echo "Server state wiped and keys regenerated"
