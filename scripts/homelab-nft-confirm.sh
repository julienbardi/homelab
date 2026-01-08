#!/bin/bash
set -euo pipefail

ROLLBACK_FLAG="/run/homelab-nft.pending"

log() { printf '%s %s\n' "$(date -Iseconds)" "$*"; }

if [ -f "$ROLLBACK_FLAG" ]; then
    log "Confirming firewall configuration."
    rm -f "$ROLLBACK_FLAG"
    systemctl stop homelab-nft-rollback.timer
else
    log "No pending firewall change."
fi
