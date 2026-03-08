#!/bin/sh
set -eu

DESIRED_PREFIX="fd89:7a3b:42c0::/48"

fatal() {
	echo "❌ $*" >&2
	exit 1
}

info() {
	echo "ℹ️  $*"
}

changed=0

current_prefix="$(nvram get ipv6_ula_prefix || true)"
current_enable="$(nvram get ipv6_ula_enable || true)"

if [ "$current_enable" != "1" ]; then
	echo "🛠️  Enabling IPv6 ULA"
	nvram set ipv6_ula_enable=1
	changed=1
fi

if [ "$current_prefix" != "$DESIRED_PREFIX" ]; then
	echo "🛠️  Setting IPv6 ULA prefix to $DESIRED_PREFIX"
	nvram set ipv6_ula_prefix="$DESIRED_PREFIX"
	changed=1
fi

if [ "$changed" -eq 1 ]; then
	echo "💾 Committing NVRAM"
	nvram commit
	echo "🔄 Restarting IPv6 (traffic interruption possible)"
	service restart_ipv6
	echo "✅ IPv6 ULA provisioning complete"
else
	echo "✅ IPv6 ULA already correctly configured"
fi
