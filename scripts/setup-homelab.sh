#!/bin/bash
set -euo pipefail
source "/home/julie/homelab/scripts/config/homelab.env"

VERSION_FILE=/var/lib/homelab-version
AUDIT_LOG=/var/log/homelab-setup.log

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
LOG_TAG="[homelab $VERSION]"

log() {
  echo "$(date -Iseconds) $LOG_TAG $1" | tee -a "$AUDIT_LOG"
}

check_service() {
  systemctl is-active "$1" >/dev/null 2>&1 && echo true || echo false
}

status_json() {
  jq -n \
    --arg dnsmasq "$(check_service ${DNSMASQ_SERVICE})" \
    --arg headscale "$(check_service headscale)" \
    '{
      dnsmasq_active: ($dnsmasq == "true"),
      headscale_active: ($headscale == "true")
    }'
}

case "${1:-}" in
  --status)
    status_json | jq
    exit 0
    ;;
esac

log "running setup"

/home/julie/homelab/scripts/deploy-homelab-dns.sh
/home/julie/homelab/scripts/firewall.sh

status_json | jq
