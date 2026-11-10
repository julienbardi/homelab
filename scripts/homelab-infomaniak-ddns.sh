#!/bin/sh
# ============================================================================
# homelab-infomaniak-ddns.sh
#
# CONTRACT
# - Updates Infomaniak DynDNS AAAA record for bardi.ch
# - Publishes the actual global IPv6 currently assigned to vmbr0
# - Does NOT decrypt secrets
# - Consumes ddns-runtime output
# - Idempotent
# ============================================================================

set -eu

DDNS_CONF="/run/user/1000/homelab/ddns/ddns.conf"

STATE_DIR="/var/lib/homelab"
STATE_FILE="${STATE_DIR}/ddns-ipv6.last"

IFACE="vmbr0"

mkdir -p "$STATE_DIR"

log() {
    printf '%s %s\n' "$(date -Iseconds)" "$*"
}

# ---------------------------------------------------------------------------
# Load runtime credentials
# ---------------------------------------------------------------------------

if [ ! -r "$DDNS_CONF" ]; then
    log "ERROR: missing DDNS runtime file: $DDNS_CONF"
    exit 1
fi

# shellcheck disable=SC1090
. "$DDNS_CONF"

: "${ddns_username:?missing ddns_username}"
: "${ddns_password:?missing ddns_password}"
: "${ddns_topdomain:?missing ddns_topdomain}"

# ---------------------------------------------------------------------------
# Discover current global IPv6
# ---------------------------------------------------------------------------

CURRENT_IPV6="$(
    ip -6 addr show dev "$IFACE" scope global \
    | awk '/inet6 2/ {print $2}' \
    | cut -d/ -f1 \
    | head -n1
)"

if [ -z "$CURRENT_IPV6" ]; then
    log "ERROR: no global IPv6 found on $IFACE"
    exit 1
fi

# ---------------------------------------------------------------------------
# Verify published DNS state
# ---------------------------------------------------------------------------

AUTH_NS="$(
    dig +short NS "$ddns_topdomain" \
    | sort \
    | head -n1 \
    | sed 's/\.$//'
)"

if [ -z "$AUTH_NS" ]; then
    log "ERROR: unable to discover authoritative nameserver"
    exit 1
fi

PUBLISHED_IPV6="$(
    dig +short AAAA "$ddns_topdomain" @"$AUTH_NS" | head -n1
)"

if [ "$CURRENT_IPV6" = "$PUBLISHED_IPV6" ]; then
    printf '%s\n' "$CURRENT_IPV6" > "$STATE_FILE"
    log "DNS already correct ($CURRENT_IPV6)"
    exit 0
fi

log "DNS mismatch detected"
log "DNS=${PUBLISHED_IPV6:-<none>}"
log "HOST=$CURRENT_IPV6"

# ---------------------------------------------------------------------------
# Update Infomaniak DynDNS
# ---------------------------------------------------------------------------

RESPONSE="$(
    curl -fsS \
        -u "${ddns_username}:${ddns_password}" \
        "https://infomaniak.com/nic/update?hostname=${ddns_topdomain}&myip6=${CURRENT_IPV6}"
)"

STATUS="$(printf '%s\n' "$RESPONSE" | awk '{print $1}')"

case "$STATUS" in
    good|nochg)
        printf '%s\n' "$CURRENT_IPV6" > "$STATE_FILE"
        log "SUCCESS: ${ddns_topdomain} -> ${CURRENT_IPV6} (${STATUS})"
        ;;
    *)
        log "ERROR: DynDNS update failed"
        log "RESPONSE=$RESPONSE"
        exit 1
        ;;
esac