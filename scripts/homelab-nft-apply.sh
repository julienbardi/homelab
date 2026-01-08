#!/bin/bash
set -euo pipefail

RULES="${HOMELAB_DIR}/scripts/homelab.nft"
ROLLBACK_FLAG="/run/homelab-nft.pending"

log() { printf '%s %s\n' "$(date -Iseconds)" "$*"; }

log "Validating nft ruleset..."
nft -c -f "$RULES"

log "Applying nft ruleset atomically..."
nft -f "$RULES"

log "Arming rollback timer..."
touch "$ROLLBACK_FLAG"
systemctl start homelab-nft-rollback.timer

log "Firewall applied. Run 'make nft-confirm' to confirm."
