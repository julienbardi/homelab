#!/bin/bash
set -euo pipefail

HOMELAB_NFT_ROLLBACK_FLAG="/run/homelab-nft.pending"

# shellcheck disable=SC2034
SCRIPT_NAME="homelab-nft-rollback"
# shellcheck disable=SC1091
source /usr/local/bin/common.sh

# If no rollback flag, nothing to do
[ -f "$HOMELAB_NFT_ROLLBACK_FLAG" ] || exit 0

log "⚠️ Rollback triggered! Restoring minimal safe firewall."

nft flush table inet homelab_filter
nft flush table ip homelab_nat

rm -f "$HOMELAB_NFT_ROLLBACK_FLAG"

log "📦 Minimal firewall restored and rollback flag cleared."
