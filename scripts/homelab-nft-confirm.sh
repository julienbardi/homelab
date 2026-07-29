#!/bin/bash
# homelab-nft-confirm.sh (debug)
set -euo pipefail

echo "DEBUG: starting homelab-nft-confirm.sh"

: "${HOMELAB_NFT_ETC_DIR:=/etc/nftables}"
: "${HOMELAB_NFT_RULESET:=${HOMELAB_NFT_ETC_DIR}/homelab.nft}"
: "${HOMELAB_NFT_HASH_FILE:=/var/lib/homelab/nftables.applied.sha256}"
: "${HOMELAB_NFT_ROLLBACK_FLAG:=/run/homelab-nft.apply}"

echo "DEBUG: HOMELAB_NFT_RULESET=$HOMELAB_NFT_RULESET"
echo "DEBUG: HOMELAB_NFT_HASH_FILE=$HOMELAB_NFT_HASH_FILE"
echo "DEBUG: HOMELAB_NFT_ROLLBACK_FLAG=$HOMELAB_NFT_ROLLBACK_FLAG"

VERBOSE="${VERBOSE:-1}"

SCRIPT_NAME="homelab-nft-confirm"
source /usr/local/bin/common.sh

echo "DEBUG: after sourcing common.sh"

if [ ! -f "$HOMELAB_NFT_RULESET" ]; then
    log "❌ Applied nftables ruleset not found: $HOMELAB_NFT_RULESET"
    echo "DEBUG: exiting with 1 (ruleset missing)"
    exit 1
fi

if [ -f "$HOMELAB_NFT_ROLLBACK_FLAG" ]; then
    log "🔍 Confirming firewall configuration ..."
    echo "DEBUG: rollback flag present"

    install -d -o root -g root -m 0755 "$(dirname "$HOMELAB_NFT_HASH_FILE")" || {
        rc=$?
        echo "DEBUG: install failed rc=$rc"
        exit $rc
    }

    sha256sum "$HOMELAB_NFT_RULESET" | awk '{print $1}' > "$HOMELAB_NFT_HASH_FILE" || {
        rc=$?
        echo "DEBUG: sha256sum/awk failed rc=$rc"
        exit $rc
    }

    rm -f "$HOMELAB_NFT_ROLLBACK_FLAG" || {
        rc=$?
        echo "DEBUG: rm failed rc=$rc"
        exit $rc
    }

    systemctl stop --no-block homelab-nft-rollback.timer || {
        rc=$?
        echo "DEBUG: systemctl stop failed rc=$rc"
        exit $rc
    }

    log "📦 Firewall confirmed and hash recorded."
    echo "DEBUG: exiting with 0 (confirmed)"
    exit 0
else
    log "ℹ️ No pending firewall change to confirm."
    echo "DEBUG: exiting with 0 (no pending change)"
    exit 0
fi
