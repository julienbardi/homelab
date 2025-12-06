#!/bin/bash
# ============================================================
# setup-subnet-router.sh
# ------------------------------------------------------------
# Supporting script: configure subnet router + WireGuard rules
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Detect conflicts against *all* current IPv4/IPv6 subnets
#   - Configure NAT (idempotent)
#   - Apply GRO tuning for performance
#   - Define firewall rules for DNS/SSH/Web UI (idempotent)
#   - Apply WireGuard firewall rules (wg0, VPN subnet bridging)
#   - Apply global conntrack safety rules
#   - Persist firewall rules safely
#   - Echo footer for auditability
# Note:
#   LAN_IF must be set to bridge0 (bridge interface) for correct routing.
#   DNS resolver reload (Unbound) is not handled here.
#
# CONTRACT:
# - Calls run_as_root with argv tokens (not quoted strings).
# - Operators (> | && ||) must be escaped when invoked from Make.
# - Script itself runs as root when called via systemd, but uses run_as_root
#   for commands that must persist or require elevated privileges.
# - ensure_rule() must be defined in scripts/common.sh and handle idempotency.
# ============================================================

set -euo pipefail
source "/home/julie/src/homelab/scripts/common.sh"

# --- Environment / topology (adjust if needed) ---
LAN_IF="bridge0"
LAN_SUBNET="10.89.12.0/24"
LAN_SUBNET_V6="2a01:8b81:4800:9c00::/64"
WG_IF="wg0"
VPN_SUBNET="10.4.0.0/24"

# Global IPv6 prefix routed/advertised for LAN (no trailing ::/64 in variable)
GLOBAL_IPV6_PREFIX="2a01:8b81:4800:9c00"
GLOBAL_PREFIX_LEN=64

# --- Interface guard ---
if ! ip link show "${LAN_IF}" | grep -q "state UP"; then
	log "ERROR: Interface ${LAN_IF} not found or not UP, aborting."
	exit 1
fi

# --- Enable IPv6 forwarding and related kernel settings ---
log "Enabling IPv6 forwarding and related kernel settings..."
run_as_root sysctl -w net.ipv6.conf.all.forwarding=1
run_as_root sysctl -w net.ipv6.conf.default.forwarding=1
run_as_root sysctl -w net.ipv6.conf."${LAN_IF}".forwarding=1
run_as_root sysctl -w net.ipv6.conf."${WG_IF}".forwarding=1
log "IPv6 forwarding enabled."

# --- Conflict detection (audit only) ---
log "Checking for subnet conflicts..."
conflicts=""
for route in $(ip -4 route show | awk '{print $1}'; ip -6 route show | awk '{print $1}'); do
	conflicts="${conflicts}${route},"
done
if [ -n "${conflicts}" ]; then
	conflicts="${conflicts%,}"  # trim trailing comma
	log "WARN: Existing subnets detected: ${conflicts}"
else
	log "No existing subnets detected."
fi

# --- NAT setup (idempotent) ---
log "Ensuring NAT MASQUERADE for ${LAN_SUBNET} via ${LAN_IF}..."
run_as_root iptables-legacy -t nat -C POSTROUTING -s "${LAN_SUBNET}" -o "${LAN_IF}" -j MASQUERADE 2>/dev/null || \
run_as_root iptables-legacy -t nat -A POSTROUTING -s "${LAN_SUBNET}" -o "${LAN_IF}" -j MASQUERADE
log "NAT MASQUERADE ensured."

# --- Firewall rules for essential services (idempotent) ---
log "Ensuring firewall INPUT rules for DNS/SSH/Web UI..."
# DNS (Unbound)
ensure_rule iptables-legacy -I INPUT -p udp --dport 53 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p tcp --dport 53 -j ACCEPT
# SSH (custom port and standard port)
ensure_rule iptables-legacy -I INPUT -p tcp --dport 2222 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p tcp --dport 22   -j ACCEPT
# UGOS Pro Web UI (nginx)
ensure_rule iptables-legacy -I INPUT -p tcp --dport 9999 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p tcp --dport 9443 -j ACCEPT
# UPnP service
ensure_rule iptables-legacy -I INPUT -p tcp --dport 49152 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p udp --dport 49152 -j ACCEPT
# wsdd2 service (Web Services Discovery)
ensure_rule iptables-legacy -I INPUT -p udp --dport 3702 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p udp --dport 5355 -j ACCEPT
# SMB file sharing
ensure_rule iptables-legacy -I INPUT -p tcp --dport 137 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p udp --dport 137 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p tcp --dport 138 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p udp --dport 138 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p tcp --dport 139 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p udp --dport 139 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p tcp --dport 445 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p udp --dport 445 -j ACCEPT

# --- Firewall rules for HTTPS and UDP ports (idempotent) ---
log "Ensuring firewall INPUT rules for HTTPS and VPN ports..."
# 443 TCP open to the world for HTTPS
ensure_rule iptables-legacy -I INPUT -p tcp --dport 443 -j ACCEPT
ensure_rule ip6tables-legacy -I INPUT -p tcp --dport 443 -j ACCEPT

# UDP 51421 only for interface bridge0  for 10.1.0/24 and 2a01:...:11::/64
ensure_rule iptables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51421 -s 10.1.0.0/24 -j ACCEPT
ensure_rule ip6tables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51421 -s ${GLOBAL_IPV6_PREFIX}:11::/64 -j ACCEPT

# UDP 51422 only for interface bridge0  for 10.2.0/24 and 2a01:...:12::/64
ensure_rule iptables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51422 -s 10.2.0.0/24 -j ACCEPT
ensure_rule ip6tables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51422 -s ${GLOBAL_IPV6_PREFIX}:12::/64 -j ACCEPT

# UDP 51423 only for interface bridge0  for 10.3.0/24 and 2a01:...:13::/64
ensure_rule iptables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51423 -s 10.3.0.0/24 -j ACCEPT
ensure_rule ip6tables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51423 -s ${GLOBAL_IPV6_PREFIX}:13::/64 -j ACCEPT

# UDP 51424 only for interface bridge0  for 10.4.0/24 and 2a01:...:14::/64
ensure_rule iptables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51424 -s 10.4.0.0/24 -j ACCEPT
ensure_rule ip6tables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51424 -s ${GLOBAL_IPV6_PREFIX}:14::/64 -j ACCEPT

# UDP 51425 only for interface bridge0  for 10.5.0/24 and 2a01:...:15::/64
ensure_rule iptables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51425 -s 10.5.0.0/24 -j ACCEPT
ensure_rule ip6tables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51425 -s ${GLOBAL_IPV6_PREFIX}:15::/64 -j ACCEPT

# UDP 51426 only for interface bridge0  for 10.6.0/24 and 2a01:...:16::/64
ensure_rule iptables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51426 -s 10.6.0.0/24 -j ACCEPT
ensure_rule ip6tables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51426 -s ${GLOBAL_IPV6_PREFIX}:16::/64 -j ACCEPT

# UDP 51427 only for interface bridge0  for 10.7.0/24 and 2a01:...:17::/64
ensure_rule iptables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51427 -s 10.7.0.0/24 -j ACCEPT
ensure_rule ip6tables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51427 -s ${GLOBAL_IPV6_PREFIX}:17::/64 -j ACCEPT

# bridge0  all ports all protocols from 10.89.12.0/24 and 2a01:8b81:4800:9c00::/64
ensure_rule iptables-legacy -I INPUT -i "${LAN_IF}" -s "${LAN_SUBNET}" -j ACCEPT
ensure_rule ip6tables-legacy -I INPUT -i "${LAN_IF}" -s "${LAN_SUBNET_V6}" -j ACCEPT

# --- Connection tracking safety rules (global) ---
log "Ensuring conntrack safety rules (ESTABLISHED,RELATED)..."
ensure_rule iptables-legacy -A INPUT   -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ensure_rule iptables-legacy -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# --- WireGuard firewall rules (wg0–wg7 profiles) ---
log "Applying WireGuard firewall rules for wg0–wg7..."

for i in {0..7}; do
	WG_IF="wg${i}"
	IPV4_SUBNET="10.${i}.0.0/24"
	# map per-interface IPv6 subnet to global prefix fragment 1${i}
	IPV6_SUBNET="${GLOBAL_IPV6_PREFIX}:1${i}::/64"
	PORT=$((51420 + i))
	PROFILE="null"

	if ip link show "${WG_IF}" >/dev/null 2>&1; then
		log "Configuring ${WG_IF} (${IPV4_SUBNET}, ${IPV6_SUBNET}, port ${PORT})..."

		# Special case: wg4 is IPv6-only
		if [[ "${i}" == "4" ]]; then
			PROFILE="IPv6-only"
			ensure_rule ip6tables-legacy -A INPUT   -i "${WG_IF}" -s "${IPV6_SUBNET}" -j ACCEPT
			ensure_rule ip6tables-legacy -A FORWARD -i "${WG_IF}" -s "${IPV6_SUBNET}" -j ACCEPT
			ensure_rule ip6tables-legacy -A FORWARD -o "${WG_IF}" -d "${IPV6_SUBNET}" -j ACCEPT
			ensure_rule ip6tables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport "${PORT}" -s "${IPV6_SUBNET}" -j ACCEPT
			log "✅ IPv6-only rules applied for wg4."
			log "Profile summary: ${WG_IF} → ${PROFILE}"
			continue
		fi

		# IPv4 baseline
		ensure_rule iptables-legacy -A INPUT   -i "${WG_IF}" -s "${IPV4_SUBNET}" -j ACCEPT
		ensure_rule iptables-legacy -A FORWARD -i "${WG_IF}" -s "${IPV4_SUBNET}" -j ACCEPT
		ensure_rule iptables-legacy -A FORWARD -o "${WG_IF}" -d "${IPV4_SUBNET}" -j ACCEPT

		# IPv6 baseline
		ensure_rule ip6tables-legacy -A INPUT   -i "${WG_IF}" -s "${IPV6_SUBNET}" -j ACCEPT
		ensure_rule ip6tables-legacy -A FORWARD -i "${WG_IF}" -s "${IPV6_SUBNET}" -j ACCEPT
		ensure_rule ip6tables-legacy -A FORWARD -o "${WG_IF}" -d "${IPV6_SUBNET}" -j ACCEPT

		# Accept UDP port for this interface
		ensure_rule iptables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport "${PORT}" -s "${IPV4_SUBNET}" -j ACCEPT
		ensure_rule ip6tables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport "${PORT}" -s "${IPV6_SUBNET}" -j ACCEPT

		# LAN access only for wg1, wg3, wg5, wg7
		if [[ "${i}" =~ ^(1|3|5|7)$ ]]; then
			PROFILE="${PROFILE}+LAN"
			ensure_rule iptables-legacy -A FORWARD -i "${WG_IF}" -d "${LAN_SUBNET}" -j ACCEPT
			ensure_rule iptables-legacy -A FORWARD -o "${WG_IF}" -s "${LAN_SUBNET}" -j ACCEPT
			ensure_rule ip6tables-legacy -A FORWARD -i "${WG_IF}" -d "${LAN_SUBNET_V6}" -j ACCEPT
			ensure_rule ip6tables-legacy -A FORWARD -o "${WG_IF}" -s "${LAN_SUBNET_V6}" -j ACCEPT
		fi

		# Internet access only for wg2, wg3, wg6, wg7
		if [[ "${i}" =~ ^(2|3|6|7)$ ]]; then
			PROFILE="${PROFILE}+Internet"
			ensure_rule iptables-legacy -t nat -A POSTROUTING -s "${IPV4_SUBNET}" -o "${LAN_IF}" -j MASQUERADE
			ensure_rule ip6tables-legacy -A FORWARD -i "${WG_IF}" -j ACCEPT
			ensure_rule ip6tables-legacy -A FORWARD -o "${WG_IF}" -j ACCEPT
		fi

		# IPv6 access for wg5, wg6, wg7 (wg4 handled separately)
		if [[ "${i}" =~ ^(5|6|7)$ ]]; then
			PROFILE="${PROFILE}+IPv6"
		fi

		log "✅ ${WG_IF} rules applied."
		log "Profile summary: ${WG_IF} → ${PROFILE}"
	else
		log "⚠️ ${WG_IF} not found, skipping."
	fi
done


# --- Tailscale firewall rules (tailscale0 specific) ---
TS_IF="tailscale0"
TS_SUBNET_V4="100.64.0.0/10"
TS_SUBNET_V6="fd7a:115c:a1e0::/48"

log "Ensuring Tailscale firewall rules..."
if ip link show "${TS_IF}" >/dev/null 2>&1; then
	# IPv4
	ensure_rule iptables-legacy -A INPUT   -i "${TS_IF}" -s "${TS_SUBNET_V4}" -j ACCEPT
	ensure_rule iptables-legacy -A FORWARD -i "${TS_IF}" -s "${TS_SUBNET_V4}" -j ACCEPT
	ensure_rule iptables-legacy -A FORWARD -o "${TS_IF}" -d "${TS_SUBNET_V4}" -j ACCEPT
	ensure_rule iptables-legacy -t nat -A POSTROUTING -s "${TS_SUBNET_V4}" -o "${LAN_IF}" -j MASQUERADE

	# IPv6
	ensure_rule ip6tables-legacy -A INPUT   -i "${TS_IF}" -s "${TS_SUBNET_V6}" -j ACCEPT
	ensure_rule ip6tables-legacy -A FORWARD -i "${TS_IF}" -s "${TS_SUBNET_V6}" -j ACCEPT
	ensure_rule ip6tables-legacy -A FORWARD -o "${TS_IF}" -d "${TS_SUBNET_V6}" -j ACCEPT
	ensure_rule ip6tables-legacy -t nat -A POSTROUTING -s "${TS_SUBNET_V6}" -o "${LAN_IF}" -j MASQUERADE

	log "Tailscale firewall rules applied: VPN ${TS_SUBNET_V4}, ${TS_SUBNET_V6} bridged to LAN ${LAN_SUBNET} via ${LAN_IF}."
else
	log "WARN: Tailscale interface ${TS_IF} not found, skipping Tailscale rules."
fi

# --- GRO tuning ---
log "Applying GRO tuning..."
if run_as_root ethtool -K "${LAN_IF}" gro off 2>/dev/null; then
	log "GRO disabled on ${LAN_IF}"
else
	log "WARN: Failed to disable GRO on ${LAN_IF}"
fi

# --- Configure NDP proxying for global IPv6 prefix (ndppd preferred) ---
log "Configuring NDP proxying for ${GLOBAL_IPV6_PREFIX}::/${GLOBAL_PREFIX_LEN}..."

if command -v ndppd >/dev/null 2>&1; then
	log "ndppd found; writing configuration and restarting service..."
	cat > /etc/ndppd.conf <<EOF
route-ttl 300
proxy ${LAN_IF} {
	router yes
	timeout 500
	ttl 300
	rule ${GLOBAL_IPV6_PREFIX}::/${GLOBAL_PREFIX_LEN} {
		auto
	}
}
EOF
	run_as_root systemctl daemon-reload || true
	run_as_root systemctl enable --now ndppd.service || true
	run_as_root systemctl restart ndppd.service || true
	run_as_root systemctl status ndppd.service --no-pager
	log "ndppd configured to proxy ${GLOBAL_IPV6_PREFIX}::/${GLOBAL_PREFIX_LEN} on ${LAN_IF}"
else
	log "ndppd not installed; attempting to install via apt..."
	if run_as_root apt-get update && run_as_root apt-get install -y ndppd; then
		log "ndppd installed; configuring..."
		cat > /etc/ndppd.conf <<EOF
route-ttl 300
proxy ${LAN_IF} {
	router yes
	timeout 500
	ttl 300
	rule ${GLOBAL_IPV6_PREFIX}::/${GLOBAL_PREFIX_LEN} {
	}
}
EOF
		run_as_root systemctl enable --now ndppd.service || true
		run_as_root systemctl restart ndppd.service || true
		log "ndppd configured to proxy ${GLOBAL_IPV6_PREFIX}::/${GLOBAL_PREFIX_LEN} on ${LAN_IF}"
	else
		log "WARN: Could not install ndppd; falling back to ip -6 neigh proxy entries for known client addresses."
		# Fallback: add explicit proxy entries for expected client addresses (idempotent)
		# This list should be extended to match actual client host addresses
		CLIENT_ADDRS=(
		  "${GLOBAL_IPV6_PREFIX}:10::2"
		  "${GLOBAL_IPV6_PREFIX}:11::2"
		  "${GLOBAL_IPV6_PREFIX}:12::2"
		  "${GLOBAL_IPV6_PREFIX}:13::2"
		  "${GLOBAL_IPV6_PREFIX}:14::2"
		  "${GLOBAL_IPV6_PREFIX}:15::2"
		  "${GLOBAL_IPV6_PREFIX}:16::2"
		  "${GLOBAL_IPV6_PREFIX}:17::2"
		)
		for addr in "${CLIENT_ADDRS[@]}"; do
			if ! ip -6 neigh show proxy | grep -q "${addr}"; then
				run_as_root ip -6 neigh add proxy "${addr}" dev "${LAN_IF}" || true
				log "Added proxy NDP for ${addr} on ${LAN_IF}"
			else
				log "Proxy NDP already present for ${addr}"
			fi
		done
	fi
fi

# Ensure kernel route for the /64 is present on the server (safe idempotent)
run_as_root ip -6 route replace ${GLOBAL_IPV6_PREFIX}::/${GLOBAL_PREFIX_LEN} dev "${WG_IF}" || true
log "Local route for ${GLOBAL_IPV6_PREFIX}::/${GLOBAL_PREFIX_LEN} -> ${WG_IF} ensured."

# --- Persist firewall rules ---
log "Persisting iptables rules to /etc/iptables/rules.v4 and /etc/iptables/rules.v6..."
if run_as_root iptables-legacy-save > /etc/iptables/rules.v4 && \
	run_as_root ip6tables-legacy-save > /etc/iptables/rules.v6; then
	log "Firewall rules persisted."
else
	log "ERROR: Failed to persist firewall rules!"
fi

# Inform about netfilter-persistent status (for restore on reboot)
if systemctl is-enabled netfilter-persistent >/dev/null 2>&1; then
	log "netfilter-persistent is enabled; rules will restore on boot."
else
	log "WARN: netfilter-persistent is NOT enabled."
	log "Enable with: sudo apt-get install -y netfilter-persistent && sudo systemctl enable --now netfilter-persistent"
fi

# --- Footer logging ---
COMMIT_HASH=$(git -C "${HOME}/src/homelab" rev-parse --short HEAD 2>/dev/null || echo "unknown")
log "Subnet router setup complete. Commit=${COMMIT_HASH}"
