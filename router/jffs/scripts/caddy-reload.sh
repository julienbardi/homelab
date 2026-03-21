#!/bin/sh
# jffs/scripts/caddy-reload.sh

# Load secrets
if [ -f "/jffs/scripts/.ddns_confidential" ]; then
    . /jffs/scripts/.ddns_confidential
    export INFOMANIAK_API_TOKEN="$DDNSPASSWORD"
fi

CADDY_BIN="/tmp/mnt/sda/router/bin/caddy"
CADDY_CONF="/etc/caddy/Caddyfile"

# Validate config first
if ! $CADDY_BIN validate --config "$CADDY_CONF" --adapter caddyfile; then
    echo "❌ Caddyfile syntax error — NOT starting"
    exit 1
fi

# Enforce convergence
echo "🧹 Stopping any running Caddy instances"
killall caddy 2>/dev/null || true

# Start cleanly (daemonized)
echo "🚀 Starting Caddy"
$CADDY_BIN start --config "$CADDY_CONF" --adapter caddyfile
echo "✅ Caddy started successfully"