#!/bin/sh
# dns-watchdog.sh — DNS health watchdog for Asuswrt-Merlin
# - Dual-domain fallback (google.com + cloudflare.com)
# - IPv4 + IPv6 DNS resolution tests
# - dnsmasq race-condition detection baked in
# - WAN restart backoff to prevent restart storms

LOGTAG="dns-watchdog"
DNSMASQ_PORT="53"

TEST_DOMAIN1="google.com"
TEST_DOMAIN2="cloudflare.com"

UPSTREAM_IP4="1.1.1.1"
UPSTREAM_IP6="2606:4700:4700::1111"

MAX_FAILS=3
STATE_FILE="/jffs/dns-watchdog.state"
BACKOFF_FILE="/jffs/dns-watchdog.backoff"

log() {
    logger -t "$LOGTAG" "$*"
}

get_fail_count() {
    [ -f "$STATE_FILE" ] && cat "$STATE_FILE" 2>/dev/null || echo 0
}

set_fail_count() {
    echo "$1" > "$STATE_FILE"
}

inc_fail() {
    FAILS="$(get_fail_count)"
    FAILS=$((FAILS + 1))
    set_fail_count "$FAILS"
    echo "$FAILS"
}

reset_fail() {
    set_fail_count 0
}

# -----------------------------
# Backoff logic
# -----------------------------

get_next_restart_time() {
    [ -f "$BACKOFF_FILE" ] && cat "$BACKOFF_FILE" 2>/dev/null || echo 0
}

set_next_restart_time() {
    echo "$1" > "$BACKOFF_FILE"
}

compute_backoff_seconds() {
    FAILS="$1"
    case "$FAILS" in
        0) echo 0 ;;
        1) echo 300 ;;     # 5 min
        2) echo 900 ;;     # 15 min
        3) echo 1800 ;;    # 30 min
        4) echo 3600 ;;    # 60 min
        *) echo 3600 ;;    # cap at 60 min
    esac
}

apply_backoff_and_restart() {
    NOW="$(date +%s)"
    NEXT_ALLOWED="$(get_next_restart_time)"

    if [ "$NOW" -lt "$NEXT_ALLOWED" ]; then
        REMAIN=$((NEXT_ALLOWED - NOW))
        log "Backoff active: skipping WAN restart (wait ${REMAIN}s)"
        return
    fi

    # Clear readiness stamp before restarting WAN/dnsmasq
    rm -f /jffs/dnsmasq-config.ready

    # Restart WAN
    log "Restarting WAN (backoff OK)"
    service restart_wan

    # Compute next backoff
    FAILS="$(get_fail_count)"
    BACKOFF="$(compute_backoff_seconds "$FAILS")"
    NEXT=$((NOW + BACKOFF))
    set_next_restart_time "$NEXT"

    log "Next WAN restart allowed in ${BACKOFF}s"
}

# -----------------------------
# dnsmasq race detection
# -----------------------------

detect_dnsmasq_race() {
    COUNT="$(ps | grep '[d]nsmasq' | wc -l)"
    if [ "$COUNT" -ne 1 ]; then
        log "RACE: Multiple dnsmasq processes detected (count=$COUNT)"
    fi

    if ! netstat -ln 2>/dev/null | grep -q ":${DNSMASQ_PORT} "; then
        log "RACE: dnsmasq not bound to port 53"
    fi

    PPID="$(ps | grep '[d]nsmasq' | awk '{print $2}')"
    if [ "$PPID" != "1" ]; then
        log "RACE: dnsmasq PPID=$PPID (expected 1)"
    fi

    if ! ip route | grep -q "default via"; then
        log "RACE: dnsmasq started before WAN was up"
    fi

    if ! grep -q "conf-dir=/jffs/configs" /etc/dnsmasq.conf; then
        log "RACE: dnsmasq missing JFFS config include"
    fi
}

invariant_dnsmasq_singleton() {
    # Verify that dnsmasq is running and bound to port 53
    if [ -z "$(pidof dnsmasq)" ]; then
        log "INVARIANT FAIL: no dnsmasq process running"
        return 1
    fi

    if ! netstat -ln 2>/dev/null | grep -q ":${DNSMASQ_PORT} "; then
        log "INVARIANT FAIL: dnsmasq not bound to port ${DNSMASQ_PORT}"
        return 1
    fi

    return 0
}

check_dnsmasq_proc() {
    [ -n "$(pidof dnsmasq)" ]
}

check_dnsmasq_port() {
    netstat -ln 2>/dev/null | grep -q ":${DNSMASQ_PORT} "
}

check_router_dns() {
    nslookup "$TEST_DOMAIN1" 127.0.0.1 >/dev/null 2>&1 && return 0
    nslookup "$TEST_DOMAIN2" 127.0.0.1 >/dev/null 2>&1 && return 0
    return 1
}

check_router_dns_ipv6() {
    nslookup "$TEST_DOMAIN1" 127.0.0.1 2>/dev/null | grep -q "Address: .*:" && return 0
    nslookup "$TEST_DOMAIN2" 127.0.0.1 2>/dev/null | grep -q "Address: .*:" && return 0
    return 1
}

check_upstream_dns() {
    ping -c1 -W1 "$UPSTREAM_IP4" >/dev/null 2>&1
}

check_upstream_dns_ipv6() {
    ping6 -c1 -W1 "$UPSTREAM_IP6" >/dev/null 2>&1
}

# -----------------------------
# Main logic
# -----------------------------

main() {
    # Suppress watchdog actions until homelab deploys dnsmasq config
    if [ ! -f /jffs/dnsmasq-config.ready ]; then
        log "dnsmasq-config.ready missing — suppressing watchdog actions"
        exit 0
    fi
    # IFC mode: run only invariants, no watchdog logic
    if [ "$1" = "--invariant" ]; then
        invariant_dnsmasq_singleton
        exit $?
    fi
    if ! check_dnsmasq_proc; then
        FAILS="$(inc_fail)"
        log "FAIL $FAILS: dnsmasq process count != 1"
        detect_dnsmasq_race

    elif ! check_dnsmasq_port; then
        FAILS="$(inc_fail)"
        log "FAIL $FAILS: no listener on port ${DNSMASQ_PORT}"
        detect_dnsmasq_race

    elif ! check_router_dns; then
        FAILS="$(inc_fail)"
        log "FAIL $FAILS: router cannot resolve ${TEST_DOMAIN1} or ${TEST_DOMAIN2} (IPv4)"
        detect_dnsmasq_race

    elif ! check_upstream_dns; then
        FAILS="$(inc_fail)"
        log "FAIL $FAILS: upstream IPv4 DNS IP ${UPSTREAM_IP4} unreachable"

    elif ! check_router_dns_ipv6; then
        FAILS="$(inc_fail)"
        log "FAIL $FAILS: IPv6 DNS resolution failed for ${TEST_DOMAIN1} or ${TEST_DOMAIN2}"

    elif ! check_upstream_dns_ipv6; then
        FAILS="$(inc_fail)"
        log "FAIL $FAILS: upstream IPv6 DNS IP ${UPSTREAM_IP6} unreachable"

    else
        if [ "$(get_fail_count)" -ne 0 ]; then
            log "DNS OK again, resetting failure counter"
        fi
        reset_fail
        set_next_restart_time 0
        exit 0
    fi

    FAILS="$(get_fail_count)"
    if [ "$FAILS" -ge "$MAX_FAILS" ]; then
        apply_backoff_and_restart
    fi
}

main "$@"
