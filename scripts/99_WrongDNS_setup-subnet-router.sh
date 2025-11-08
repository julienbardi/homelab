#!/bin/bash
set -euo pipefail
source "/home/julie/homelab/scripts/config/homelab.env"

VERSION_FILE=/var/lib/homelab-subnet-router.version
LOG_TAG="[subnet-router]"

increment_version() {
  if [[ -f "$VERSION_FILE" ]]; then
    CUR=$(cat "$VERSION_FILE")
    MAJOR=$(echo "$CUR" | cut -d. -f1 | tr -d v)
    MINOR=$(echo "$CUR" | cut -d. -f2)
    echo "v${MAJOR}.$((MINOR+1))" > "$VERSION_FILE"
  else
    echo "v0.1" > "$VERSION_FILE"
  fi
  cat "$VERSION_FILE"
}

VERSION=$(increment_version)

log() {
  echo "$(date -Iseconds) $LOG_TAG $1"
}

# --- Conflict detection ---
check_conflicts() {
  for net in $(docker network ls --format '{{.Name}}' | xargs -n1 docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}'); do
    if ipcalc -c "$net" "$LAN_SUBNET" >/dev/null 2>&1; then
      log "⚠️ Conflict detected: Docker subnet $net overlaps with LAN $LAN_SUBNET"
      exit 1
    fi
  done
}

# --- NAT setup ---
setup_nat() {
  WAN_IF=$(ip route | awk '/default/ {print $5; exit}')
  iptables -t nat -A POSTROUTING -s "$LAN_SUBNET" -o "$WAN_IF" -j MASQUERADE
  log "NAT configured for $LAN_SUBNET via $WAN_IF"
}

# --- dnsmasq restart ---
restart_dnsmasq() {
  systemctl restart "$DNSMASQ_SERVICE"
  log "dnsmasq restarted ($DNSMASQ_SERVICE)"
}

# --- Tailscale advertisement ---
advertise_routes() {
  tailscale up \
    --login-server="$TAILSCALE_LOGIN_SERVER" \
    --advertise-routes="$LAN_SUBNET" \
    --accept-routes \
    --reset
  log "Tailscale advertising $LAN_SUBNET"
}

# --- GRO tuning ---
tune_gro() {
  for iface in $(ls /sys/class/net); do
    if [[ -f "/sys/class/net/$iface/gro_flush_timeout" ]]; then
      echo 0 > "/sys/class/net/$iface/gro_flush_timeout" || true
      log "GRO tuning applied on $iface"
    fi
  done
}

# --- Main ---
log "Starting subnet router setup $VERSION"
check_conflicts
setup_nat
restart_dnsmasq
advertise_routes
tune_gro
log "Completed subnet router setup $VERSION at $(date -Iseconds)"
