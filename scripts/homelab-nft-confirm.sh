#!/bin/bash
set -euo pipefail

HOMELAB_NFT_ETC_DIR="/etc/nftables"
HOMELAB_NFT_RULESET="${HOMELAB_NFT_ETC_DIR}/homelab.nft"
HOMELAB_NFT_HASHFILE="/var/lib/homelab/nftables.applied.sha256"
HOMELAB_NFT_ROLLBACK_FLAG="/run/homelab-nft.pending"

log() { printf '%s %s\n' "$(date -Iseconds)" "$*"; }

if [ ! -f "$HOMELAB_NFT_RULESET" ]; then
	log "ERROR: Applied nftables ruleset not found: $HOMELAB_NFT_RULESET"
	exit 1
fi

if [ -f "$HOMELAB_NFT_ROLLBACK_FLAG" ]; then
	log "Confirming firewall configuration."

	install -d -o root -g root -m 0755 "$(dirname "$HOMELAB_NFT_HASHFILE")"
	sha256sum "$HOMELAB_NFT_RULESET" | awk '{print $1}' > "$HOMELAB_NFT_HASHFILE"

	rm -f "$HOMELAB_NFT_ROLLBACK_FLAG"
	systemctl stop --no-block homelab-nft-rollback.timer

	log "Firewall confirmed and hash recorded."
else
	log "No pending firewall change."
fi
