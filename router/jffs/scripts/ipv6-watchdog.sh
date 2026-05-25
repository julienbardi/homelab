#!/bin/sh

# ipv6-watchdog.sh
# Ensures WAN IPv6 stays healthy.
# Tiered escalation:
#   1. Restart dhcp6c after N failures
#   2. Full WAN reset if kernel IPv6 stack is broken

WAN_RESET="/jffs/scripts/wan-reset.sh"
STATE_FILE="/jffs/scripts/.ipv6_watchdog_state"
FAIL_THRESHOLD=3

log() {
    logger -t ipv6-watchdog "$1"
}

# Detect WAN IPv6 GUA
WAN_GUA=$(ip -6 addr show eth0 | awk '/global/ {print $2}')

# Detect kernel-level IPv6 failure
BROKEN=0
grep -q "Failed to send RS" /tmp/syslog.log && BROKEN=1
grep -q "Cannot assign requested address" /tmp/syslog.log && BROKEN=1

if [ "$BROKEN" -eq 1 ]; then
    log "Kernel IPv6 stack broken — escalating to WAN reset"
    [ -x "$WAN_RESET" ] && "$WAN_RESET"
    exit 0
fi

# If WAN IPv6 is healthy → reset failure counter
if [ -n "$WAN_GUA" ]; then
    echo 0 > "$STATE_FILE"
    log "WAN IPv6 healthy"
    exit 0
fi

# WAN IPv6 missing → increment failure counter
FAILS=0
[ -f "$STATE_FILE" ] && FAILS=$(cat "$STATE_FILE")
FAILS=$((FAILS + 1))
echo "$FAILS" > "$STATE_FILE"

log "WAN IPv6 missing ($FAILS consecutive failures)"

# Tier 1: restart dhcp6c
if [ "$FAILS" -lt "$FAIL_THRESHOLD" ]; then
    log "Restarting dhcp6c"
    killall dhcp6c 2>/dev/null
    sleep 1
    dhcp6c -c /tmp/dhcp6c.conf -p /var/run/dhcp6c.pid eth0
    exit 0
fi

# Tier 2: escalate to WAN reset
log "Failure threshold reached — escalating to WAN reset"
[ -x "$WAN_RESET" ] && "$WAN_RESET"

# Reset counter after escalation
echo 0 > "$STATE_FILE"
exit 0
