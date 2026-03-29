#!/bin/sh
# provision-ipv6-ula.sh
set -eu

# 🛑 GUARD: Ensure the Makefile actually sent the prefix
: "${DESIRED_ULA_PREFIX:?Error: DESIRED_ULA_PREFIX environment variable not set}"

# Extract the pure prefix (strip /48 if present) to build the ::1 address
CLEAN_PREFIX=$(echo "$DESIRED_ULA_PREFIX" | sed 's/\/.*//')
ROUTER_ULA_ADDR="${CLEAN_PREFIX}1"

# --- NEW: Define the NAS DNS Target ---
DESIRED_DNS="fd89:7a3b:42c0::4"

# Check current router state
current_enable="$(nvram get ipv6_ula_enable 2>/dev/null || echo "0")"
current_prefix="$(nvram get ipv6_ula_prefix 2>/dev/null || echo "")"
current_dns="$(nvram get ipv6_dns1 2>/dev/null || echo "")" # --- NEW: Get current DNS ---

changed=0

# Logic 1: Is ULA enabled?
if [ "$current_enable" != "1" ]; then
    echo "🟢 Enabling IPv6 ULA (NVRAM)"
    nvram set ipv6_ula_enable=1
    changed=1
fi

# Logic 2: Does the prefix match our Single Source of Truth?
if [ "$current_prefix" != "$DESIRED_ULA_PREFIX" ]; then
    echo "🟢 Setting ULA prefix → $DESIRED_ULA_PREFIX"
    nvram set ipv6_ula_prefix="$DESIRED_ULA_PREFIX"
    changed=1
fi

# Logic 3: Interface Assignment (The "Constructor" Fix)
if ! ip -6 addr show dev br0 | grep -qi "$CLEAN_PREFIX"; then
    echo "🌐 Assigning ULA IP to br0 → $ROUTER_ULA_ADDR"
    ip -6 addr add "$ROUTER_ULA_ADDR/64" dev br0
    changed=1
else
    echo "✅ br0 already owns a ULA address in $CLEAN_PREFIX"
fi

# --- NEW: Logic 4: DNS Advertisement (RDNSS) ---
if [ "$current_dns" != "$DESIRED_DNS" ]; then
    echo "🟢 Setting IPv6 DNS (RDNSS) → $DESIRED_DNS"
    nvram set ipv6_dns1="$DESIRED_DNS"
    # Note: Setting dns61_x ensures compatibility across Merlin firmware variants
    nvram set ipv6_dns61_x="$DESIRED_DNS"
    changed=1
else
    echo "✅ IPv6 DNS already points to $DESIRED_DNS"
fi

# Logic 5: Commit and trigger if something changed
if [ "$changed" -eq 1 ]; then
    echo "💾 Committing NVRAM and restarting services..."
    nvram commit
    service restart_dnsmasq
    echo "🚀 ULA and DNS are now being advertised via dnsmasq."
else
    echo "✅ ULA and DNS configuration is converged. No action needed."
fi