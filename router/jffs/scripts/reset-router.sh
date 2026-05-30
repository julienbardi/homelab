#!/bin/sh
# reset-router.sh
# Deterministic router cleanup to restore pristine Merlin state
# Preconditions:
#   - Must run on AsusWRT-Merlin
#   - Must run as root
#   - JFFS must be mounted

set -eu

echo "[reset] starting router reset…"

# --- PRECONDITION CHECKS -----------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    echo "[reset] ERROR: must run as root" >&2
    exit 1
fi

if [ ! -d /jffs ]; then
    echo "[reset] ERROR: /jffs not mounted" >&2
    exit 1
fi

# --- REMOVE ALL USER SCRIPTS -------------------------------------------------

echo "[reset] clearing /jffs/scripts…"
if [ -d /jffs/scripts ]; then
    find /jffs/scripts -type f -maxdepth 1 -print -delete
fi

# --- REMOVE ALL DNSMASQ OVERRIDES -------------------------------------------

echo "[reset] clearing /jffs/configs…"
if [ -d /jffs/configs ]; then
    find /jffs/configs -type f -maxdepth 1 -print -delete
fi

# --- REMOVE ALL WIREGUARD INTERFACES ----------------------------------------

echo "[reset] removing WireGuard interfaces if present…"
for iface in wg0 wg1 wg2 wg3 wg4 wg5 wg6 wg7; do
    if ip link show "$iface" >/dev/null 2>&1; then
        echo "[reset]   deleting $iface"
        wg-quick down "$iface" 2>/dev/null || true
        ip link del "$iface" 2>/dev/null || true
    fi
done

# --- CLEAR NAT66 TABLE -------------------------------------------------------

echo "[reset] clearing NAT66…"
ip6tables -t nat -F || true

# --- CLEAR IPV4 NAT (SAFE) ---------------------------------------------------

echo "[reset] clearing IPv4 NAT user chains…"
iptables -t nat -F || true

# --- CLEAR TAILSCALE (OPTIONAL) ----------------------------------------------

if command -v tailscale >/dev/null 2>&1; then
    echo "[reset] tailscale detected, resetting state…"
    tailscale down 2>/dev/null || true
    rm -f /var/lib/tailscale/tailscaled.state || true
fi

# --- RESTART WAN -------------------------------------------------------------

echo "[reset] restarting WAN…"
service restart_wan

# --- VERIFY DNSMASQ ----------------------------------------------------------

echo "[reset] verifying dnsmasq syntax…"
if ! dnsmasq --test; then
    echo "[reset] ERROR: dnsmasq syntax invalid after reset" >&2
    exit 1
fi

# --- VERIFY IPV6 -------------------------------------------------------------

echo "[reset] verifying IPv6 prefix on br0…"
if ! ip -6 addr show br0 | grep -q "scope global"; then
    echo "[reset] WARNING: no global IPv6 on br0 (WWZ may be slow)"
else
    echo "[reset] IPv6 OK"
fi

# --- VERIFY NAT TABLES CLEAN -------------------------------------------------

echo "[reset] verifying NAT tables…"
ip6tables -t nat -L -n -v
iptables -t nat -L -n -v

echo "[reset] router reset complete."
