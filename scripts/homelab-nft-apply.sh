#!/bin/bash
# homelab-nft-apply.sh
set -euo pipefail

HOMELAB_DIR="${HOMELAB_DIR:-$(realpath "$(dirname "$0")/..")}"

HOMELAB_NFT_ETC_DIR="/etc/nftables"
HOMELAB_NFT_RULES_SRC="${HOMELAB_DIR}/scripts/homelab.nft"
HOMELAB_NFT_RULESET="${HOMELAB_NFT_ETC_DIR}/homelab.nft"
HOMELAB_NFT_ROLLBACK_FLAG="/run/homelab-nft.pending"

log() { printf '%s %s\n' "$(date -Iseconds)" "$*"; }

log "Ensuring nftables config directory exists..."
install -d -o root -g root -m 0755 "$HOMELAB_NFT_ETC_DIR"

log "Installing nftables ruleset..."
install -o root -g root -m 0644 "$HOMELAB_NFT_RULES_SRC" "$HOMELAB_NFT_RULESET"

log "Validating nft ruleset..."
nft -c -f "$HOMELAB_NFT_RULESET"

log "Applying nft ruleset atomically..."
nft -f "$HOMELAB_NFT_RULESET"

log "Arming rollback timer..."
touch "$HOMELAB_NFT_ROLLBACK_FLAG"
systemctl start homelab-nft-rollback.timer

log "Firewall applied. Run 'make nft-confirm' to confirm."
