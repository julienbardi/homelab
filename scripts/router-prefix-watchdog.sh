#!/usr/bin/env bash
# --------------------------------------------------------------------
# router-prefix-watchdog.sh  (NAS-side marker executor)
#
# IMPORTANT:
#   - This script runs on the NAS, NOT on the router.
#   - It does NOT detect prefix changes.
#   - Prefix detection is done by router-side WAN-event or Makefile logic.
#   - This script ONLY consumes the marker:
#         /var/lib/homelab/router-prefix.changed
#     and triggers router-all when present.
# --------------------------------------------------------------------
set -euo pipefail


MARKER="/var/lib/homelab/router-prefix.changed"
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
    fi

    sleep 5
done
