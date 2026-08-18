#!/bin/bash
# homelab-nft-confirm.sh
set -euo pipefail

: "${HOMELAB_NFT_ETC_DIR:=/etc/nftables}"
: "${HOMELAB_NFT_RULESET:=${HOMELAB_NFT_ETC_DIR}/homelab.nft}"
: "${STAMP_DIR_ROOT:=${HOME}/.local/state/homelab}"
: "${HOMELAB_NFT_HASH_FILE:=${STAMP_DIR_ROOT}/nftables.applied.sha256}"
: "${HOMELAB_NFT_ROLLBACK_FLAG:=/run/homelab-nft.apply}"

VERBOSE="${VERBOSE:-1}"

SCRIPT_NAME="homelab-nft-confirm"
source /usr/local/bin/common.sh

if [ ! -f "$HOMELAB_NFT_RULESET" ]; then
    log "❌ Applied nftables ruleset not found: $HOMELAB_NFT_RULESET"
    exit 1
fi

if [ -f "$HOMELAB_NFT_ROLLBACK_FLAG" ]; then
    log "🔍 Confirming firewall configuration ..."

    install -d -o root -g root -m 0755 "$(dirname "$HOMELAB_NFT_HASH_FILE")" || {
        rc=$?
        exit $rc
    }

    sha256sum "$HOMELAB_NFT_RULESET" | awk '{print $1}' > "$HOMELAB_NFT_HASH_FILE" || {
        rc=$?
        exit $rc
    }

    rm -f "$HOMELAB_NFT_ROLLBACK_FLAG" || {
        rc=$?
        exit $rc
    }

    systemctl stop --no-block homelab-nft-rollback.timer || {
        rc=$?
        exit $rc
    }

    log "📦 Firewall confirmed and hash recorded."
    exit 0
else
    log "ℹ️ No pending firewall change to confirm."
    exit 0
fi
