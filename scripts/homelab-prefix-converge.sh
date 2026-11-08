#!/bin/sh
# homelab-prefix-converge.sh
set -eu

# Load environment configuration first so STAMP_DIR_ROOT is authoritative
ENV_FILE="/etc/homelab/homelab-prefix.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: Missing $ENV_FILE. Please run 'make homelab-prefix-env' first." >&2
    exit 1
fi
# shellcheck disable=SC1090
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

if [ -z "$NEW_PREFIX_RAW" ] || [ -z "$NEW_PREFIX" ]; then
    log "ERROR: Empty delegated prefix in stamp file"
    rm -f "$MARKER"
    exit 1
fi

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
    echo 2 > /proc/sys/net/ipv6/conf/"$NAS_LAN_IFACE"/accept_ra || log "WARN: failed to set $NAS_LAN_IFACE/accept_ra"
else
    log "WARN: /proc/sys/net/ipv6/conf/$NAS_LAN_IFACE does not exist"
fi

# 3. Restart networkd to re-trigger SLAAC + DHCPv6 hooks
log "RESTARTING systemd-networkd"
systemctl restart systemd-networkd || log "WARN: systemd-networkd restart failed"

# 4. Wait for global IPv6 to reappear
TIMEOUT=30

while [ "$TIMEOUT" -gt 0 ]; do
    if ip -6 addr show dev "$NAS_LAN_IFACE" | grep -Eq 'inet6 2[0-9a-f]'; then
        log "OK: Global IPv6 address restored"
        break
    fi

    sleep 1
    TIMEOUT=$((TIMEOUT - 1))
done

if [ "$TIMEOUT" -eq 0 ]; then
    log "ERROR: Global IPv6 address did not reappear"
    rm -f "$MARKER"
    exit 1
fi

# 5. Force DHCPv6 renew (if dhcp6c exists)
if command -v dhcp6c >/dev/null 2>&1; then
    log "DHCP6C RENEW on $NAS_LAN_IFACE"
    dhcp6c -c /etc/dhcp6c.conf "$NAS_LAN_IFACE" || log "WARN: dhcp6c renew failed"
else
    log "INFO: dhcp6c not present, skipping DHCPv6 renew"
fi

# 6. Wait for the RA default route to return
TIMEOUT=30

while [ "$TIMEOUT" -gt 0 ]; do
    if ip -6 route show default | grep -q "dev $NAS_LAN_IFACE"; then
        log "OK: IPv6 default route restored"
        break
    fi

    sleep 1
    TIMEOUT=$((TIMEOUT - 1))
done

if [ "$TIMEOUT" -eq 0 ]; then
    log "ERROR: IPv6 default route failed to return"
    rm -f "$MARKER"
    exit 1
fi

# 7. Verify prefix is actually present on interface
if ip -6 addr show dev "$NAS_LAN_IFACE" | grep -Fq "${NEW_PREFIX}"; then
    log "OK: New prefix present on $NAS_LAN_IFACE"
else
    log "ERROR: New prefix NOT present on $NAS_LAN_IFACE"
    rm -f "$MARKER"
    exit 1
fi

# 8. Verify IPv6 default route exists
if ip -6 route show default | grep -q "dev $NAS_LAN_IFACE"; then
    log "OK: IPv6 default route present"
else
    log "ERROR: No IPv6 default route in table main"
    rm -f "$MARKER"
    exit 1
fi

# 9. Restart resolver to pick up new IPv6 DNS (non-fatal if resolved service is absent)
if systemctl list-unit-files 2>/dev/null | grep -q '^systemd-resolved.service'; then
    log "RESTARTING systemd-resolved"
    systemctl restart systemd-resolved || log "WARN: systemd-resolved restart failed"
else
    log "INFO: systemd-resolved not installed"
fi

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
        WG_IF="$IF"

        WG_V6=$(awk -v ifc="$WG_IF" '
            $1 == ifc { print $6 }
        ' "$TSV")

        if [ -z "$WG_V6" ]; then
            log "WARN: no IPv6 definition found for $WG_IF in $TSV"
            continue
        fi

        SUBNET_ID=$(printf '%s\n' "$WG_V6" \
        | awk -F: '{print $(NF-1)}')

        if [ -z "$SUBNET_ID" ] || [ "$SUBNET_ID" = "$WG_V6" ]; then
            log "ERROR: failed to derive subnet id from $WG_V6"
            continue
        fi

        ULA_PREFIX="${ULA_BASE}:${SUBNET_ID}::"
        WG_GUA="${WG_PREFIX_BASE}:${SUBNET_ID}::1/64"

        log "${WG_IF}: desired global = $WG_GUA"

        ip link show "$WG_IF" >/dev/null 2>&1 || {
            log "${WG_IF}: interface missing, skipping"
            continue
        }

        ip -6 addr show dev "$WG_IF" scope global \
          | awk '/inet6/ {print $2}' \
          | while read -r addr; do
                case "$addr" in
                    ${ULA_PREFIX}*/64) ;;
                    "$WG_GUA") ;;
                    *)
                        log "${WG_IF}: removing stale global $addr"
                        ip -6 addr del "$addr" dev "$WG_IF" 2>/dev/null || true
                        ;;
                esac
            done

        if ! ip -6 addr show dev "$WG_IF" scope global | grep -q "${WG_GUA%/*}"; then
            log "${WG_IF}: adding global $WG_GUA"
            ip -6 addr add "$WG_GUA" dev "$WG_IF" 2>/dev/null || \
                log "${WG_IF}: WARN: failed to add $WG_GUA"
        else
            log "${WG_IF}: global already present"
        fi

        log "${WG_IF}: dual-stack converge complete (ULA + GUA)"
    done
else
    log "WARN: WG interfaces TSV not found at $TSV, skipping WG GUA assignment"
fi

# 13. Clear marker
rm -f "$MARKER"
log "DONE: marker cleared, converge cycle complete"