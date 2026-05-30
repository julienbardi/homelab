#!/bin/sh

# Safe WAN IPv6 recovery for AsusWRT-Merlin
# Only resets WAN when IPv6 is actually broken

log() {
    logger -t wan-reset "$1"
}

# Detect broken IPv6 state
BROKEN=0

# No global IPv6?
WAN_GUA=$(ip -6 addr show eth0 | awk '/global/ {print $2}')
[ -z "$WAN_GUA" ] && BROKEN=1

# dhcp6c errors in syslog?
grep -q "Failed to send RS" /tmp/syslog.log && BROKEN=1
grep -q "Cannot assign requested address" /tmp/syslog.log && BROKEN=1

if [ "$BROKEN" -eq 0 ]; then
    log "IPv6 WAN healthy — no reset needed"
    exit 0
fi

log "IPv6 WAN broken — performing full WAN reset"

service stop_wan
sleep 3
ifconfig eth0 down
sleep 2
ifconfig eth0 up
sleep 2
service start_wan
service restart_ipv6

log "WAN reset complete"
exit 0
