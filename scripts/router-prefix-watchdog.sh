#!/usr/bin/env bash
# --------------------------------------------------------------------
# router-prefix-watchdog.sh  (NAS-side marker executor)
#
# IMPORTANT:
#   - This script runs on the NAS, NOT on the router.
#   - It does NOT detect prefix changes.
#   - Prefix detection is done by router-side WAN-event or Makefile logic.
#   - This script ONLY consumes the marker:
#         $(STAMP_DIR_ROOT)/router-prefix.changed
#     and triggers router-all when present.
# --------------------------------------------------------------------
set -euo pipefail

: "${STAMP_DIR_ROOT:=${HOME}/.local/state/homelab}"
MARKER="${STAMP_DIR_ROOT}/router-prefix.changed"
LOGTAG="router-prefix-watchdog"

# REPO_ROOT must be exported by systemd service
: "${REPO_ROOT:?REPO_ROOT must be exported by systemd unit}"

[[ -d "$REPO_ROOT" ]] || {
    logger -t "$LOGTAG" "ERROR: REPO_ROOT does not exist: $REPO_ROOT"
    exit 1
}

logger -t "$LOGTAG" "Starting watchdog (repo: $REPO_ROOT)"

# Prevent log from growing beyond 1MB
if [[ -f /var/log/router-prefix-watchdog.log ]] && \
   [[ $(wc -c < /var/log/router-prefix-watchdog.log) -gt 1048576 ]]; then
    : > /var/log/router-prefix-watchdog.log
fi

while true; do
    if [[ -f "$MARKER" ]]; then
        logger -t "$LOGTAG" "Prefix-change marker detected — running router-all"
        rm -f "$MARKER"

        # Run converge
        make -C "$REPO_ROOT" router-all \
            >> /var/log/router-prefix-watchdog.log 2>&1 || \
            logger -t "$LOGTAG" "router-all failed"

        logger -t "$LOGTAG" "router-all completed"

        #
        # --- NAS IPv6 HEAL BLOCK -----------------------------------------
        #
        logger -t "$LOGTAG" "Running NAS IPv6 heal block"

        logger -t "$LOGTAG" "Checking NAS IPv6 reachability after prefix change..."

        ROUTER_ULA="fd89:7a3b:42c0::1"

        if ping6 -c1 -W1 "$ROUTER_ULA" >/dev/null 2>&1; then
            logger -t "$LOGTAG" "IPv6 to router OK — no heal needed"
        else
            logger -t "$LOGTAG" "IPv6 to router broken — healing NAS IPv6 stack"

            ip -6 addr flush dev eth0
            ip -6 route flush default
            systemctl restart homelab-network || true
            sleep 3

            if ping6 -c1 -W2 "$ROUTER_ULA" >/dev/null 2>&1; then
                logger -t "$LOGTAG" "IPv6 to router restored successfully"
            else
                logger -t "$LOGTAG" "IPv6 still broken after heal attempt"
            fi
        fi
        #
        # -----------------------------------------------------------------

    fi

    sleep 5
done
