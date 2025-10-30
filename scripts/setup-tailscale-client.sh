#!/bin/bash
set -euo pipefail
source "/home/julie/homelab/scripts/config/homelab.env"

log() {
  echo "[tailscale-client] $(date -Iseconds) $1"
}

# Ensure tailscale is installed
if ! command -v tailscale >/dev/null 2>&1; then
  log "❌ tailscale binary not found"
  exit 1
fi

# Bring up tailscale client with Headscale coordination
log "Starting Tailscale client..."
tailscale up \
  --login-server="${TAILSCALE_LOGIN_SERVER}" \
  --accept-routes \
  --accept-dns=false \
  --advertise-routes="${TAILSCALE_ADVERTISE_ROUTES}" \
  --reset

# Confirm status
log "Tailscale status:"
tailscale status
