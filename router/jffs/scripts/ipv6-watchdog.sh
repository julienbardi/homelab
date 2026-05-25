#!/bin/sh

# ipv6-watchdog.sh
# Router-side IPv6 PD watchdog for AsusWRT-Merlin.
# - Checks for global IPv6 on WAN
# - If missing for N consecutive runs, restarts dhcp6c
# - Designed to be called periodically via cru (cron)

STATE_FILE="/jffs/ipv6-watchdog.state"
MIN_FAILS=3   # how many consecutive failures before action
LOG_TAG="ipv6-watchdog"

wan_if="$(nvram get wan0_ifname)"

if [ -z "$wan_if" ]; then
  logger -t "$LOG_TAG" "wan0_ifname is empty, aborting"
  exit 1
fi

# Does WAN have a global IPv6 address?
if ip -6 addr show dev "$wan_if" | grep -q "scope global"; then
  # IPv6 OK → reset failure counter
  echo 0 > "$STATE_FILE"
  exit 0
fi

# No global IPv6 → increment failure counter
fails=0
if [ -f "$STATE_FILE" ]; then
  fails="$(cat "$STATE_FILE" 2>/dev/null || echo 0)"
fi

fails=$((fails + 1))
echo "$fails" > "$STATE_FILE"

if [ "$fails" -lt "$MIN_FAILS" ]; then
  logger -t "$LOG_TAG" "No WAN IPv6 (fail $fails/$MIN_FAILS), waiting"
  exit 0
fi

logger -t "$LOG_TAG" "No WAN IPv6 for $fails consecutive checks, restarting dhcp6c"
echo 0 > "$STATE_FILE"

/usr/sbin/service restart_dhcp6c
