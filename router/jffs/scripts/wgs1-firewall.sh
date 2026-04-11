#!/bin/sh
# /jffs/scripts/wgs1-firewall.sh
# Idempotent firewall rules for router WireGuard interface wgs1
set -eu

log() {
    printf '[wgs1-fw] %s\n' "$*" >&2
}

rule() {
    # rule <add|del> <iptables|ip6tables> <args...>
    op="$1"; shift
    bin="$1"; shift

    if [ "$op" = add ]; then
        if ! $bin -C "$@" 2>/dev/null; then
            log "ADD: $bin $*"
            $bin -A "$@"
        else
            log "SKIP(add): $bin $*"
        fi
    else
        if $bin -C "$@" 2>/dev/null; then
            log "DEL: $bin $*"
            $bin -D "$@"
        else
            log "SKIP(del): $bin $*"
        fi
    fi
}

IFACE="wgs1"

case "${1:-}" in
    up)
        log "Applying router firewall rules for ${IFACE}"

        # Allow forwarding through wgs1
        rule add iptables  FORWARD -i "${IFACE}" -j ACCEPT
        rule add iptables  FORWARD -o "${IFACE}" -j ACCEPT

        # NAT for outbound traffic
        rule add iptables -t nat POSTROUTING -o eth0 -j MASQUERADE

        ;;

    down)
        log "Removing router firewall rules for ${IFACE}"

        rule del iptables  FORWARD -i "${IFACE}" -j ACCEPT
        rule del iptables  FORWARD -o "${IFACE}" -j ACCEPT

        rule del iptables -t nat POSTROUTING -o eth0 -j MASQUERADE

        ;;

    *)
        log "Usage: $0 {up|down}"
        exit 1
        ;;
esac
