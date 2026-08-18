#!/bin/sh
# homelab-prefix-converge.sh
set -eu

# Load environment configuration first so STAMP_DIR_ROOT is authoritative
ENV_FILE="/etc/homelab/homelab-prefix.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: Missing $ENV_FILE. Please run 'make homelab-prefix-env' first." >&2
    exit 1
fi
. "$ENV_FILE"

if [ -z "${STAMP_DIR_ROOT:-}" ]; then
    echo "ERROR: STAMP_DIR_ROOT is not defined in $ENV_FILE." >&2
    exit 1
fi

MARKER="${STAMP_DIR_ROOT}/router-prefix.changed"
STAMP="${STAMP_DIR_ROOT}/router-prefix.last"
LOG_DIR="/var/log/homelab"
LOG="${LOG_DIR}/homelab-prefix.log"

# Exit fast if no marker
[ ! -f "$MARKER" ] && exit 0

log() {
    MSG="$(date -Iseconds) $*"
    echo "$MSG"
    if mkdir -p "$LOG_DIR" 2>/dev/null && touch "$LOG" 2>/dev/null; then
        echo "$MSG" >> "$LOG"
    else
        logger -t homelab-prefix-converge "$*"
    fi
}

log "PREFIX WATCHDOG TRIGGERED"

if [ -z "${HOMELAB_ROOT:-}" ]; then
    log "ERROR: HOMELAB_ROOT is not defined"
    echo "ERROR: HOMELAB_ROOT is not defined. Please ensure $ENV_FILE is up-to-date." >&2
    exit 1
fi

if [ -z "${NAS_LAN_IFACE:-}" ]; then
    log "ERROR: NAS_LAN_IFACE is not defined"
    echo "ERROR: NAS_LAN_IFACE is not defined. Please ensure $ENV_FILE is up-to-date." >&2
    exit 1
fi

if [ -z "${ULA_BASE:-}" ]; then
    log "ERROR: ULA_BASE is not defined"
    echo "ERROR: ULA_BASE is not defined. Please ensure $ENV_FILE is up-to-date." >&2
    exit 1
fi

# Read new prefix (normalized to ::)
if [ ! -f "$STAMP" ]; then
    log "ERROR: STAMP file missing: $STAMP"
    exit 1
fi

NEW_PREFIX_RAW=$(cat "$STAMP")
NEW_PREFIX=$(printf '%s\n' "$NEW_PREFIX_RAW" | sed 's/::.*$/::/')
log "NEW PREFIX (raw) = $NEW_PREFIX_RAW"
log "NEW PREFIX (norm) = $NEW_PREFIX"

# 1. Flush stale global IPv6 addresses while preserving the ULA prefix
log "FLUSHING OLD GLOBAL ADDRESSES on $NAS_LAN_IFACE (preserving ULA)"
ip -6 addr show dev "$NAS_LAN_IFACE" scope global \
  | awk '/inet6/ {print $2}' \
  | while read -r addr; do
        case "$addr" in
            ${ULA_BASE}*) ;; # keep ULA address
            *)
                log "Removing stale global address $addr"
                ip -6 addr del "$addr" dev "$NAS_LAN_IFACE" 2>/dev/null || true
                ;;
        esac
    done

# 2. Force RA acceptance
log "SETTING accept_ra = 2 (host mode with forwarding)"
echo 2 > /proc/sys/net/ipv6/conf/all/accept_ra || log "WARN: failed to set all/accept_ra"
if [ -d "/proc/sys/net/ipv6/conf/$NAS_LAN_IFACE" ]; then
    echo 2 > /proc/sys/net/ipv6/conf/$NAS_LAN_IFACE/accept_ra || log "WARN: failed to set $NAS_LAN_IFACE/accept_ra"
else
    log "WARN: /proc/sys/net/ipv6/conf/$NAS_LAN_IFACE does not exist"
fi

# 3. Restart networkd to re-trigger SLAAC + DHCPv6 hooks
log "RESTARTING systemd-networkd"
systemctl restart systemd-networkd || log "WARN: systemd-networkd restart failed"

# 4. Wait for addresses to appear
sleep 3

# 5. Force DHCPv6 renew (if dhcp6c exists)
if command -v dhcp6c >/dev/null 2>&1; then
    log "DHCP6C RENEW on $NAS_LAN_IFACE"
    dhcp6c -c /etc/dhcp6c.conf "$NAS_LAN_IFACE" || log "WARN: dhcp6c renew failed"
else
    log "INFO: dhcp6c not present, skipping DHCPv6 renew"
fi

# 6. Rebuild routing table
log "FLUSHING IPv6 ROUTES (table main)"
ip -6 route flush table main || log "WARN: route flush failed"

log "RESTARTING systemd-networkd (post-route-flush)"
systemctl restart systemd-networkd || log "WARN: systemd-networkd restart (2nd) failed"

# 7. Verify prefix is actually present on interface
if ip -6 addr show dev "$NAS_LAN_IFACE" | grep -q "${NEW_PREFIX}"; then
    log "OK: New prefix present on $NAS_LAN_IFACE"
else
    log "ERROR: New prefix NOT present on $NAS_LAN_IFACE"
fi

# 8. Verify IPv6 default route exists
if ip -6 route | grep -q "default via"; then
    log "OK: IPv6 default route present"
else
    log "ERROR: No IPv6 default route in table main"
fi

# 9. Restart resolver to pick up new IPv6 DNS (non-fatal if resolved service is absent)
log "RESTARTING systemd-resolved"
systemctl restart systemd-resolved || log "WARN: systemd-resolved restart failed"

# 10. Verify IPv6 egress (ICMP)
if ping6 -c1 -W1 2001:4860:4860::8888 >/dev/null 2>&1; then
    log "OK: IPv6 egress (ICMP) to 2001:4860:4860::8888"
else
    log "ERROR: IPv6 egress (ICMP) FAILED to 2001:4860:4860::8888"
fi

# 11. Verify DNS over IPv6 via local resolver (::1)
if command -v dig >/dev/null 2>&1; then
    if dig +short AAAA google.com @::1 >/dev/null 2>&1; then
        log "OK: DNS over IPv6 via ::1 (google.com AAAA)"
    else
        log "ERROR: DNS over IPv6 via ::1 FAILED (google.com AAAA)"
    fi
else
    log "INFO: dig not available, skipping DNS IPv6 verification"
fi

# 12. Assign global IPv6 to all NAS-hosted, enabled WG interfaces. Source of truth: wg-interfaces.tsv
TSV="${HOMELAB_ROOT}/wireguard/input/wg-interfaces.tsv"
WG_PREFIX_BASE=$(printf '%s' "$NEW_PREFIX" | sed 's/::$//')

if [ -f "$TSV" ]; then
    WG_LIST=$(awk '
        $1 ~ /^wg[0-9]+$/ && $2=="nas" && $7==1 {print $1}
    ' "$TSV")

    for IF in $WG_LIST; do
        IDX=$(echo "$IF" | sed 's/wg//')
        HEX_SUFFIX=$(printf "%02x" "$IDX")

        WG_IF="$IF"
        ULA_PREFIX="${ULA_BASE}:${IDX}::"
        WG_GUA="${WG_PREFIX_BASE}${HEX_SUFFIX}::1/64"

        log "WG${IDX}: desired global = $WG_GUA"

        ip link show "$WG_IF" >/dev/null 2>&1 || {
            log "WG${IDX}: interface missing, skipping"
            continue
        }

        ip -6 addr show dev "$WG_IF" scope global \
          | awk '/inet6/ {print $2}' \
          | while read -r addr; do
                case "$addr" in
                    ${ULA_PREFIX}*/64) ;;
                    "$WG_GUA") ;;
                    *)
                        log "WG${IDX}: removing stale global $addr"
                        ip -6 addr del "$addr" dev "$WG_IF" 2>/dev/null || true
                        ;;
                esac
            done

        if ! ip -6 addr show dev "$WG_IF" scope global | grep -q "${WG_GUA%/*}"; then
            log "WG${IDX}: adding global $WG_GUA"
            ip -6 addr add "$WG_GUA" dev "$WG_IF" 2>/dev/null || \
                log "WG${IDX}: WARN: failed to add $WG_GUA"
        else
            log "WG${IDX}: global already present"
        fi

        log "WG${IDX}: dual-stack converge complete (ULA + GUA)"
    done
else
    log "WARN: WG interfaces TSV not found at $TSV, skipping WG GUA assignment"
fi

# 13. Clear marker
rm -f "$MARKER"
log "DONE: marker cleared, converge cycle complete"