#!/bin/bash
set -euo pipefail
# resolve repo root relative to this script, allow override via HOMELAB_DIR
HOMELAB_DIR="${HOMELAB_DIR:-$(realpath "$(dirname "$0")/..")}"

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
