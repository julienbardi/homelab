#!/bin/sh
# homelab-prefix-converge.sh
set -eu

MARKER="/var/lib/homelab/router-prefix.changed"
STAMP="/var/lib/homelab/router-prefix.last"
LOG="/var/log/homelab-prefix.log"
IFACE="eth0"

# Exit fast if no marker
[ ! -f "$MARKER" ] && exit 0

log() {
    echo "$(date -Iseconds) $*" >> "$LOG"
}

log "PREFIX WATCHDOG TRIGGERED"

# Read new prefix (normalized to ::)
if [ ! -f "$STAMP" ]; then
    log "ERROR: STAMP file missing: $STAMP"
    exit 1
fi

NEW_PREFIX_RAW=$(cat "$STAMP")
NEW_PREFIX=$(printf '%s\n' "$NEW_PREFIX_RAW" | sed 's/::.*$/::/')
log "NEW PREFIX (raw) = $NEW_PREFIX_RAW"
log "NEW PREFIX (norm) = $NEW_PREFIX"

# 1. Flush stale IPv6 addresses
log "FLUSHING OLD GLOBAL ADDRESSES on $IFACE"
ip -6 addr flush dev "$IFACE" scope global || log "WARN: ip -6 addr flush failed (non-fatal)"

# 2. Force RA acceptance
log "SETTING accept_ra = 2 (host mode with forwarding)"
echo 2 > /proc/sys/net/ipv6/conf/all/accept_ra || log "WARN: failed to set all/accept_ra"
echo 2 > /proc/sys/net/ipv6/conf/$IFACE/accept_ra || log "WARN: failed to set $IFACE/accept_ra"

# 3. Restart networkd to re-trigger SLAAC + DHCPv6 hooks
log "RESTARTING systemd-networkd"
systemctl restart systemd-networkd || log "WARN: systemd-networkd restart failed"

# 4. Wait for addresses to appear
sleep 3

# 5. Force DHCPv6 renew (if dhcp6c exists)
if command -v dhcp6c >/dev/null 2>&1; then
    log "DHCP6C RENEW on $IFACE"
    dhcp6c -c /etc/dhcp6c.conf "$IFACE" || log "WARN: dhcp6c renew failed"
else
    log "INFO: dhcp6c not present, skipping DHCPv6 renew"
fi

# 6. Rebuild routing table
log "FLUSHING IPv6 ROUTES (table main)"
ip -6 route flush table main || log "WARN: route flush failed"

log "RESTARTING systemd-networkd (post-route-flush)"
systemctl restart systemd-networkd || log "WARN: systemd-networkd restart (2nd) failed"

# 7. Verify prefix is actually present on interface
if ip -6 addr show dev "$IFACE" | grep -q "${NEW_PREFIX}"; then
    log "OK: New prefix present on $IFACE"
else
    log "ERROR: New prefix NOT present on $IFACE"
fi

# 8. Verify IPv6 default route exists
if ip -6 route | grep -q "default via"; then
    log "OK: IPv6 default route present"
else
    log "ERROR: No IPv6 default route in table main"
fi

# 9. Restart resolver to pick up new IPv6 DNS
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
TSV="/root/src/homelab/wireguard/input/wg-interfaces.tsv"
ULA_BASE="fd89:7a3b:42c0"
WG_PREFIX_BASE=$(printf '%s' "$NEW_PREFIX" | sed 's/::$//')  # e.g. 2a01:8b81:4800:9c

# Extract enabled NAS interfaces
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

    # Skip if interface does not exist
    ip link show "$WG_IF" >/dev/null 2>&1 || {
        log "WG${IDX}: interface missing, skipping"
        continue
    }

    # Remove stale globals (keep ULA + desired GUA)
    ip -6 addr show dev "$WG_IF" scope global \
      | awk '/inet6/ {print $2}' \
      | while read -r addr; do
            case "$addr" in
                ${ULA_PREFIX}*/64) ;;   # keep ULA
                "$WG_GUA") ;;           # keep desired GUA
                *)
                    log "WG${IDX}: removing stale global $addr"
                    ip -6 addr del "$addr" dev "$WG_IF" 2>/dev/null || true
                    ;;
            esac
        done

    # Ensure desired GUA present (match without CIDR)
    if ! ip -6 addr show dev "$WG_IF" scope global | grep -q "${WG_GUA%/*}"; then
        log "WG${IDX}: adding global $WG_GUA"
        ip -6 addr add "$WG_GUA" dev "$WG_IF" 2>/dev/null || \
            log "WG${IDX}: WARN: failed to add $WG_GUA"
    else
        log "WG${IDX}: global already present"
    fi

    log "WG${IDX}: dual-stack converge complete (ULA + GUA)"
done

# 13. Clear marker
rm -f "$MARKER"
log "DONE: marker cleared, converge cycle complete"
