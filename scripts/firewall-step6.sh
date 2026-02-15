#!/bin/sh
# firewall-step6.sh
# OWNER: router-firewall-step6
# CONTRACT: Router mutation exclusivity
#
# INPUTS:
#   - WG_INTERFACES (resolved list)
#   - Per-interface flags:
#       <wg>_reach_lan_v4
#       <wg>_reach_lan_v6
#       <wg>_reach_wan_v4
#       <wg>_reach_wan_v6
#   - Router interfaces:
#       WAN_IF
#       LAN_IF
#
# OUTPUTS:
#   - IPv4 chain: WG_FWD4
#   - IPv6 chain: WG_FWD6
#   - Scoped FORWARD jumps for wg+
#
# BEHAVIOR:
#   - Create and flush WG_FWD4 / WG_FWD6
#   - Enforce scoped FORWARD hooks
#   - Allow ESTABLISHED,RELATED
#   - Emit per-interface allow rules
#
# NON-GOALS:
#   - No NAT
#   - No DNS policy (added later)
#   - No default DROP (added later)
#
# EXECUTION:
#   - Router-resident only
#   - Invoked by firewall lifecycle
#   - Never executed by Make
#
set -e
cd "$(dirname "$0")"

# NOTE: This script intentionally refuses execution unless:
#   - it resides in /jffs/scripts
#   - it is invoked as ./firewall-step6.sh from /jffs/scripts
if [ "$(pwd -P)" != "/jffs/scripts" ]; then
	echo "REFUSING: must be executed from /jffs/scripts on the router"
	exit 1
fi
case "$0" in
	./firewall-step6.sh) : ;;
	*) echo "REFUSING: must be invoked as ./firewall-step6.sh from /jffs/scripts"; exit 1 ;;
esac

# Required inputs
[ -n "${WG_INTERFACES:-}" ] || { echo "WG_INTERFACES is empty or undefined"; exit 1; }
[ -n "${LAN_IF:-}" ]        || { echo "LAN_IF is empty or undefined"; exit 1; }
[ -n "${WAN_IF:-}" ]        || { echo "WAN_IF is empty or undefined"; exit 1; }

# Tool availability (BusyBox)
IPT=/usr/sbin/iptables
IP6T=/usr/sbin/ip6tables

[ -x "$IPT" ]  || { echo "iptables not found at $IPT"; exit 1; }
[ -x "$IP6T" ] || { echo "ip6tables not found at $IP6T"; exit 1; }

# Ensure WireGuard forwarding chains
$IPT  -N WG_FWD4 2>/dev/null || true
$IPT  -F WG_FWD4

$IP6T -N WG_FWD6 2>/dev/null || true
$IP6T -F WG_FWD6

# Enforce scoped FORWARD hooks (IPv4)
while $IPT -C FORWARD -j WG_FWD4 2>/dev/null; do
	$IPT -D FORWARD -j WG_FWD4
done
while $IPT -C FORWARD -i wg+ -j WG_FWD4 2>/dev/null; do
	$IPT -D FORWARD -i wg+ -j WG_FWD4
done
while $IPT -C FORWARD -o wg+ -j WG_FWD4 2>/dev/null; do
	$IPT -D FORWARD -o wg+ -j WG_FWD4
done
$IPT -I FORWARD 1 -i wg+ -j WG_FWD4
$IPT -I FORWARD 2 -o wg+ -j WG_FWD4

# Enforce scoped FORWARD hooks (IPv6)
while $IP6T -C FORWARD -j WG_FWD6 2>/dev/null; do
	$IP6T -D FORWARD -j WG_FWD6
done
while $IP6T -C FORWARD -i wg+ -j WG_FWD6 2>/dev/null; do
	$IP6T -D FORWARD -i wg+ -j WG_FWD6
done
while $IP6T -C FORWARD -o wg+ -j WG_FWD6 2>/dev/null; do
	$IP6T -D FORWARD -o wg+ -j WG_FWD6
done
$IP6T -I FORWARD 1 -i wg+ -j WG_FWD6
$IP6T -I FORWARD 2 -o wg+ -j WG_FWD6

# Allow return traffic
$IPT  -A WG_FWD4 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
$IP6T -A WG_FWD6 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Per-interface allow rules
for WG_IF in $WG_INTERFACES; do
	echo "→ $WG_IF"

	# IPv4 LAN reach
	eval "v=\${${WG_IF}_reach_lan_v4:-}"
	if [ "$v" = "yes" ]; then
		$IPT -A WG_FWD4 -i "$WG_IF" -o "$LAN_IF" -j ACCEPT
	fi

	# IPv4 WAN reach
	eval "v=\${${WG_IF}_reach_wan_v4:-}"
	if [ "$v" = "yes" ]; then
		$IPT -A WG_FWD4 -i "$WG_IF" -o "$WAN_IF" -j ACCEPT
	fi

	# IPv6 LAN reach
	eval "v=\${${WG_IF}_reach_lan_v6:-}"
	if [ "$v" = "yes" ]; then
		$IP6T -A WG_FWD6 -i "$WG_IF" -o "$LAN_IF" -j ACCEPT
	fi

	# IPv6 WAN reach
	eval "v=\${${WG_IF}_reach_wan_v6:-}"
	if [ "$v" = "yes" ]; then
		$IP6T -A WG_FWD6 -i "$WG_IF" -o "$WAN_IF" -j ACCEPT
	fi
done
# End of Step 6 — WireGuard forwarding firewall
