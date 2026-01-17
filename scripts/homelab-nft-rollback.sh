#!/bin/bash
set -euo pipefail

HOMELAB_NFT_ROLLBACK_FLAG="/run/homelab-nft.pending"

log() { printf '%s %s\n' "$(date -Iseconds)" "$*"; }

[ -f "$HOMELAB_NFT_ROLLBACK_FLAG" ] || exit 0

log "Rollback triggered! Restoring minimal safe firewall."

nft flush table inet homelab_filter
nft flush table ip homelab_nat

rm -f "$HOMELAB_NFT_ROLLBACK_FLAG"
