#!/bin/bash
# homelab-nft-apply.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC2034
SCRIPT_NAME="homelab-nft-apply"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

: "${HOMELAB_NFT_ETC_DIR:=/etc/nftables}"
: "${HOMELAB_NFT_RULESET:=${HOMELAB_NFT_ETC_DIR}/homelab.nft}"
: "${STAMP_DIR_ROOT:=${HOME}/.local/state/homelab}"
: "${HOMELAB_NFT_HASH_FILE:=${STAMP_DIR_ROOT}/nftables.applied.sha256}"
: "${HOMELAB_NFT_ROLLBACK_FLAG:=/run/homelab-nft.pending}"

if [[ ! -f "$HOMELAB_NFT_RULESET" ]]; then
  log "❌ Ruleset file not found at: $HOMELAB_NFT_RULESET"
  exit 1
fi

log "🛡️ Running homelab firewall safety validator..."
run_as_root /usr/local/bin/validate-nft.sh || {
    log "❌ Firewall safety validation failed — aborting apply"
    exit 1
}

log "🔧 Ensuring nftables config directory exists..."
run_as_root install -d -o root -g root -m 0755 "$HOMELAB_NFT_ETC_DIR"

log "🔍 Validating nft ruleset..."
run_as_root nft -c -f "$HOMELAB_NFT_RULESET"

log "🚀 Applying nft ruleset atomically..."
run_as_root nft -f "$HOMELAB_NFT_RULESET"

log "ℹ️ Arming rollback timer..."
run_as_root touch "$HOMELAB_NFT_ROLLBACK_FLAG"
run_as_root systemctl start homelab-nft-rollback.timer

log "✅ Firewall applied. Run 'make nft-confirm' to confirm."
