#!/bin/sh
# /jffs/scripts/ipv6-watchdog.sh
# Runtime IPv6 health enforcement for Merlin routers.
# Implements deterministic, tiered convergence:
#   • Tier 0 — Forwarding invariants (fix drift immediately)
#   • Tier 1 — RA resync (rebuild default route)
#   • Tier 2 — Restart WAN (recover DHCPv6-PD / RA state)
#   • Tier 3 — Full WAN reset (kernel IPv6 stack failure)
# LAN prefix delegation is explicitly non-fatal per network contract.
# Only WAN_GUA + default route define IPv6 health.

WAN_RESET="/jffs/scripts/wan-reset.sh"
STATE_FILE="/jffs/scripts/.ipv6_watchdog_state"
FAIL_THRESHOLD=3
WAN_IF="eth0"

log() {
    logger -t ipv6-watchdog "$1"
}

# Detect WAN IPv6 GUA
WAN_GUA=$(ip -6 addr show "$WAN_IF" | awk '/global/ {print $2}')

# Detect LAN IPv6 GUA
LAN_GUA=$(ip -6 addr show br0 | awk '/global/ {print $2}')

# Detect delegated prefix on br0 (Merlin-safe)
PREFIX_OK=0
ip -6 route | grep -qE "^[0-9a-fA-F:]+:/64 .* dev br0" && PREFIX_OK=1

# Detect default route (Merlin-safe)
DEFRT_OK=0
ip -6 route | grep -q "^default " && DEFRT_OK=1

# Detect kernel-level IPv6 failure
BROKEN=0
grep -q "Failed to send RS" /tmp/syslog.log && BROKEN=1
grep -q "Cannot assign requested address" /tmp/syslog.log && BROKEN=1
grep -q "no default router" /tmp/syslog.log && BROKEN=1

# Forwarding invariants:
# Merlin frequently resets forwarding flags after WAN events.
# Sysctl writes may take ~50–150ms to propagate, so reads can be stale.
# Hardened detection + sync ensures Tier 0 never produces false positives.
fix_forwarding() {
    echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
    echo 1 > /proc/sys/net/ipv6/conf/br0/forwarding
    echo 1 > /proc/sys/net/ipv6/conf/"$WAN_IF"/forwarding
    sync
}

# Safe sysctl reader:
# Treat any missing file, read error, or non-"1" value as failure.
# Ensures fail-fast behavior and eliminates silent forwarding drift.
read_flag() {
    val=$(cat "$1" 2>/dev/null | tr -d '\r\n')
    [ "$val" = "1" ] && return 0
    return 1
}

forwarding_ok() {
    read_flag /proc/sys/net/ipv6/conf/all/forwarding &&
    read_flag /proc/sys/net/ipv6/conf/br0/forwarding &&
    read_flag /proc/sys/net/ipv6/conf/"$WAN_IF"/forwarding
}

# RA resync
resync_ra() {
    echo 0 > /proc/sys/net/ipv6/conf/"$WAN_IF"/accept_ra
    sleep 1
    echo 2 > /proc/sys/net/ipv6/conf/"$WAN_IF"/accept_ra
}

# Tier 3: full WAN reset
if [ "$BROKEN" -eq 1 ]; then
    log "Kernel IPv6 stack broken — escalating to WAN reset"
    [ -x "$WAN_RESET" ] && "$WAN_RESET"
    exit 0
fi

# Tier 0 — Forwarding invariants:
# Must be correct before evaluating any other IPv6 state.
# If forwarding cannot be restored, force Tier 1 by clearing DEFRT_OK.
# This guarantees RA resync → WAN restart → WAN reset escalation chain.
# Prevents the scenario where manual service restart_wan is required.
if ! forwarding_ok; then
    log "Forwarding flags incorrect — fixing"
    fix_forwarding
    sleep 1
    if ! forwarding_ok; then
        log "Forwarding still incorrect after fix — escalating"
        # Force Tier‑1 RA resync path to run
        DEFRT_OK=0
    fi
fi

# If WAN IPv6 is healthy → no escalation needed.
# - Internal hosts use ULA
# - Delegated prefix is only required for NAS NAT66 egress
# - WAN_GUA + default route define IPv6 health
# Never restart WAN solely due to missing LAN prefix delegation.
if [ -n "$WAN_GUA" ] && [ "$DEFRT_OK" -eq 1 ]; then
    echo 0 > "$STATE_FILE"
    chmod 600 "$STATE_FILE" 2>/dev/null || true
    if [ -z "$LAN_GUA" ] || [ "$PREFIX_OK" -eq 0 ]; then
        log "WAN IPv6 healthy (LAN prefix delegation absent — non-fatal, NAS NAT66 may be limited)"
    else
        log "WAN IPv6 healthy"
    fi
    exit 0
fi

if [ -z "$WAN_GUA" ] || [ "$DEFRT_OK" -eq 0 ]; then
    log "WAN IPv6 invariants failed: wan_gua=${WAN_GUA:+1} defrt=$DEFRT_OK (lan_gua=${LAN_GUA:+1} prefix=$PREFIX_OK — informational)"
fi

# Tier 1: RA resync if WAN GUA exists but no default route
if [ -n "$WAN_GUA" ] && [ "$DEFRT_OK" -eq 0 ]; then
    log "Have WAN GUA but no default route — forcing RA resync"
    resync_ra
    sleep 5
    ip -6 route | grep -q "^default " && {
        log "Default route restored via RA"
        exit 0
    }
fi

# Tier 2: WAN restart if any core invariant missing
FAILS=0
[ -f "$STATE_FILE" ] && FAILS=$(cat "$STATE_FILE")
FAILS=$((FAILS + 1))
echo "$FAILS" > "$STATE_FILE"
chmod 600 "$STATE_FILE" 2>/dev/null || true

log "IPv6 invariants missing ($FAILS consecutive failures)"

if [ "$FAILS" -lt "$FAIL_THRESHOLD" ]; then
    log "Restarting WAN for IPv6 recovery"
    service restart_wan_if 2>/dev/null || true
    service restart_wan
    exit 0
fi

# Tier 3: escalate to WAN reset
log "Failure threshold reached — escalating to WAN reset"
[ -x "$WAN_RESET" ] && "$WAN_RESET"

echo 0 > "$STATE_FILE"
chmod 600 "$STATE_FILE" 2>/dev/null || true
exit 0
