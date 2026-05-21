#!/bin/sh
# dns-enforcer.sh
# Contract:
#   - If NAS DNS (IPv4+IPv6) is healthy → force all LAN DNS to NAS
#   - If NAS DNS is unhealthy → force all LAN DNS to router
#   - No direct DNS to WAN/ISP from LAN
#   - Idempotent, BusyBox-safe

# --- CONFIG (adapt to your LAN if needed) ---
NAS_IP4="10.89.12.4"
ROUTER_IP4="10.89.12.1"

NAS_IP6="fd89:7a3b:42c0::4"
ROUTER_IP6="fd89:7a3b:42c0::1"

LAN_IF="br0"

CHAIN4="DNS_ENFORCER4"
CHAIN6="DNS_ENFORCER6"

STATE_FILE="/jffs/config/dns-enforcer.state"

log() {
    logger -t dns-enforcer "$1"
}

# --- Health check NAS DNS (IPv4 + IPv6) ---
check_dns() {
    # Prefer drill if present
    if command -v drill >/dev/null 2>&1; then
        drill @${NAS_IP4} google.com >/dev/null 2>&1 || return 1
        drill @${NAS_IP6} google.com AAAA >/dev/null 2>&1 || return 1
        return 0
    fi

    # Fallback to nslookup
    nslookup google.com ${NAS_IP4} >/dev/null 2>&1 || return 1
    nslookup -query=AAAA google.com ${NAS_IP6} >/dev/null 2>&1 || return 1
    return 0
}

# --- Decide target resolver ---
if check_dns; then
    TARGET4="${NAS_IP4}"
    TARGET6="${NAS_IP6}"
    NEW_STATE="NAS_UP"
else
    TARGET4="${ROUTER_IP4}"
    TARGET6="${ROUTER_IP6}"
    NEW_STATE="NAS_DOWN"
fi

OLD_STATE=""
[ -f "${STATE_FILE}" ] && OLD_STATE="$(cat "${STATE_FILE}" 2>/dev/null || true)"

if [ "${OLD_STATE}" != "${NEW_STATE}" ]; then
    log "State change: ${OLD_STATE} → ${NEW_STATE} (IPv4=${TARGET4}, IPv6=${TARGET6})"
    echo "${NEW_STATE}" > "${STATE_FILE}"
else
    log "State unchanged: ${NEW_STATE} (IPv4=${TARGET4}, IPv6=${TARGET6})"
fi

# --- Ensure chains exist and are hooked ---

# IPv4
iptables -t nat -L ${CHAIN4} >/dev/null 2>&1 || {
    log "Creating IPv4 chain ${CHAIN4}"
    iptables -t nat -N ${CHAIN4}
}
iptables -t nat -C PREROUTING -i ${LAN_IF} -j ${CHAIN4} >/dev/null 2>&1 || {
    log "Linking PREROUTING → ${CHAIN4} on ${LAN_IF}"
    iptables -t nat -A PREROUTING -i ${LAN_IF} -j ${CHAIN4}
}

# IPv6
ip6tables -t nat -L ${CHAIN6} >/dev/null 2>&1 || {
    log "Creating IPv6 chain ${CHAIN6}"
    ip6tables -t nat -N ${CHAIN6}
}
ip6tables -t nat -C PREROUTING -i ${LAN_IF} -j ${CHAIN6} >/dev/null 2>&1 || {
    log "Linking PREROUTING → ${CHAIN6} on ${LAN_IF}"
    ip6tables -t nat -A PREROUTING -i ${LAN_IF} -j ${CHAIN6}
}

# --- Flush and repopulate rules atomically ---

# IPv4: redirect all LAN DNS to TARGET4
iptables -t nat -F ${CHAIN4}
iptables -t nat -A ${CHAIN4} -p udp --dport 53 -j DNAT --to-destination ${TARGET4}:53
iptables -t nat -A ${CHAIN4} -p tcp --dport 53 -j DNAT --to-destination ${TARGET4}:53

# IPv6: redirect all LAN DNS to TARGET6
ip6tables -t nat -F ${CHAIN6}
ip6tables -t nat -A ${CHAIN6} -p udp --dport 53 -j DNAT --to-destination [${TARGET6}]:53
ip6tables -t nat -A ${CHAIN6} -p tcp --dport 53 -j DNAT --to-destination [${TARGET6}]:53

log "DNS enforcement active: IPv4→${TARGET4}, IPv6→${TARGET6}"
exit 0
