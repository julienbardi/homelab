#!/bin/bash
# homelab-nft-apply.sh
set -euo pipefail

# shellcheck disable=SC2034
SCRIPT_NAME="homelab-nft-apply"
# shellcheck disable=SC1091
source /usr/local/bin/common.sh

HOMELAB_NFT_ETC_DIR="/etc/nftables"
# The Makefile already synced the ruleset to HOMELAB_NFT_RULESET
HOMELAB_NFT_RULESET="/etc/nftables/homelab.nft"
HOMELAB_NFT_RULES_SRC="$HOMELAB_NFT_RULESET"
HOMELAB_NFT_ROLLBACK_FLAG="/run/homelab-nft.pending"

if [[ ! -f "$HOMELAB_NFT_RULES_SRC" ]]; then
  log "❌ Ruleset file not found at: $HOMELAB_NFT_RULES_SRC"
  exit 1
fi

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
