#!/bin/sh
# dns-enforcer.sh
# Contract:
#   - If NAS IPv4 DNS is healthy → force all LAN DNS to NAS (IPv4 + IPv6→Unbound:8553)
#   - If NAS IPv4 DNS is unhealthy → force all LAN DNS to router (IPv4 + IPv6)
#   - Idempotent, BusyBox-safe

# --- CONFIG ---
NAS_IP4="10.89.12.4"
ROUTER_IP4="10.89.12.1"

NAS_IP6="fd89:7a3b:42c0::4"
ROUTER_IP6="fd89:7a3b:42c0::1"

LAN_IF="br0"

CHAIN4="DNS_ENFORCER4"
CHAIN6="DNS_ENFORCER6"

STATE_FILE="/jffs/configs/dns-enforcer.state"
mkdir -p /jffs/configs

log() {
    logger -t dns-enforcer "$1"
}

# --- IPv4-only health check ---
check_dns() {
    nslookup google.com "${NAS_IP4}" >/dev/null 2>&1 || return 1
    return 0
}

# --- Decide target resolvers ---
if check_dns; then
    TARGET4="${NAS_IP4}"
    TARGET6_PORT="8553"        # Unbound IPv6 listener
    TARGET6="${NAS_IP6}"
    NEW_STATE="NAS_UP"
else
    TARGET4="${ROUTER_IP4}"
    TARGET6_PORT="53"
    TARGET6="${ROUTER_IP6}"
    NEW_STATE="NAS_DOWN"
fi

OLD_STATE=""
[ -f "${STATE_FILE}" ] && OLD_STATE="$(cat "${STATE_FILE}" 2>/dev/null || true)"

# --- Ensure chains exist and are hooked (cheap, safe every run) ---
iptables -t nat -L "${CHAIN4}" >/dev/null 2>&1 || {
    log "Creating IPv4 chain ${CHAIN4}"
    iptables -t nat -N "${CHAIN4}"
}
iptables -t nat -C PREROUTING -i "${LAN_IF}" -j "${CHAIN4}" >/dev/null 2>&1 || {
    log "Linking PREROUTING → ${CHAIN4} on ${LAN_IF}"
    iptables -t nat -A PREROUTING -i "${LAN_IF}" -j "${CHAIN4}"
}

ip6tables -t nat -L "${CHAIN6}" >/dev/null 2>&1 || {
    log "Creating IPv6 chain ${CHAIN6}"
    ip6tables -t nat -N "${CHAIN6}"
}
ip6tables -t nat -C PREROUTING -i "${LAN_IF}" -j "${CHAIN6}" >/dev/null 2>&1 || {
    log "Linking PREROUTING → ${CHAIN6} on ${LAN_IF}"
    ip6tables -t nat -A PREROUTING -i "${LAN_IF}" -j "${CHAIN6}"
}

# --- Only mutate NAT + RDNSS on state change ---
if [ "${OLD_STATE}" != "${NEW_STATE}" ]; then
    log "State change: ${OLD_STATE} → ${NEW_STATE} (IPv4=${TARGET4}, IPv6=[${TARGET6}]:${TARGET6_PORT})"
    echo "${NEW_STATE}" > "${STATE_FILE}"

    # Flush and repopulate IPv4 rules
    iptables -t nat -F "${CHAIN4}"
    iptables -t nat -A "${CHAIN4}" -p udp --dport 53 -j DNAT --to-destination "${TARGET4}:53"
    iptables -t nat -A "${CHAIN4}" -p tcp --dport 53 -j DNAT --to-destination "${TARGET4}:53"

    # Flush and repopulate IPv6 rules (REDIRECT)
    ip6tables -t nat -F "${CHAIN6}"
    ip6tables -t nat -A "${CHAIN6}" -p udp --dport 53 -j REDIRECT --to-ports "${TARGET6_PORT}"
    ip6tables -t nat -A "${CHAIN6}" -p tcp --dport 53 -j REDIRECT --to-ports "${TARGET6_PORT}"

    # IPv6 RDNSS advertisement control
    CURRENT_RDNSS="$(nvram get ipv6_dns1)"
    if [ "${NEW_STATE}" = "NAS_UP" ]; then
        DESIRED_RDNSS="${NAS_IP6}"
    else
        DESIRED_RDNSS="${ROUTER_IP6}"
    fi

    if [ "${CURRENT_RDNSS}" != "${DESIRED_RDNSS}" ]; then
        nvram set ipv6_dns1="${DESIRED_RDNSS}"
        nvram set ipv6_dns2=""
        nvram commit
        service restart_ipv6
        log "IPv6 RDNSS updated: advertising ${DESIRED_RDNSS}"
    else
        log "IPv6 RDNSS unchanged: still advertising ${CURRENT_RDNSS}"
    fi

    log "DNS enforcement updated: IPv4→${TARGET4}, IPv6→[${TARGET6}]:${TARGET6_PORT}"
else
    log "State unchanged: ${NEW_STATE} (no NAT/RDNSS changes applied)"
fi

exit 0
