#!/bin/sh
# ============================================================
# homelab-prefix-watchdog.sh — IPv6 prefix drift detector
#
# DEPENDS:
#   (none)
#
# CONTRACT:
# - Installed script; must not reference repo paths.
# - Must be fully self-contained (systemd does not pass env vars).
# - BusyBox-safe.
# ============================================================

set -eu

# Deterministic homelab topology (safe to hardcode)
ROUTER_HOST="julie@10.89.12.1"
ROUTER_PORT="2222"
ROUTER_IFACE="br0"
LOCAL_IFACE="eth0"

# ------------------------------------------------------------
# Extract current IPv6 address (local)
# ------------------------------------------------------------
CURRENT="$(ip -6 addr show dev "$LOCAL_IFACE" \
    | grep 'scope global' \
    | awk '{print $2}' \
    | cut -d/ -f1)"

# ------------------------------------------------------------
# Extract authoritative IPv6 address (router)
# ------------------------------------------------------------
ROUTER="$(ssh "$ROUTER_HOST" -p "$ROUTER_PORT" \
    "ip -6 addr show dev $ROUTER_IFACE | grep 'scope global' | awk '{print \$2}' | cut -d/ -f1")"

# ------------------------------------------------------------
# If either side has no IPv6, skip
# ------------------------------------------------------------
if [ -z "$CURRENT" ] || [ -z "$ROUTER" ]; then
    exit 0
fi

# ------------------------------------------------------------
# Compare IPv6 prefixes (first 4 hextets)
# ------------------------------------------------------------
PREFIX_CURRENT="$(echo "$CURRENT" | cut -d: -f1-4)"
PREFIX_ROUTER="$(echo "$ROUTER" | cut -d: -f1-4)"

if [ "$PREFIX_CURRENT" != "$PREFIX_ROUTER" ]; then
    echo "IPv6 prefix drift detected — refreshing RA"
    systemctl restart networking || systemctl restart systemd-networkd
fi
