#!/bin/sh
# provision-ipv6-ula.sh
set -eu

DESIRED_PREFIX="fd89:7a3b:42c0::/48"

current_enable="$(nvram get ipv6_ula_enable 2>/dev/null || echo "")"
current_prefix="$(nvram get ipv6_ula_prefix 2>/dev/null || echo "")"

changed=0

if [ "$current_enable" != "1" ]; then
    echo "🟢 Enabling IPv6 ULA"
    nvram set ipv6_ula_enable=1
    changed=1
fi

if [ "$current_prefix" != "$DESIRED_PREFIX" ]; then
    echo "🟢 Setting ULA prefix → $DESIRED_PREFIX"
    nvram set ipv6_ula_prefix="$DESIRED_PREFIX"
    changed=1
fi

if [ "$changed" -eq 1 ]; then
    echo "💾 Committing NVRAM (no IPv6 restart)"
    nvram commit
    echo "ℹ️  ULA will activate automatically on next reboot or dnsmasq reload"
else
    echo "✅ ULA already configured"
fi
