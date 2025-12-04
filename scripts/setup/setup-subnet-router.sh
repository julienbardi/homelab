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

LAN_IF="bridge0"
LAN_SUBNET="10.89.12.0/24"
WG_IF="wg0"
VPN_SUBNET="10.4.0.0/24"

# --- Interface guard ---
if ! ip link show "${LAN_IF}" | grep -q "state UP"; then
	log "ERROR: Interface ${LAN_IF} not found or not UP, aborting."
	exit 1
fi

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

# UDP 51421 only for interface bridge0  for 10.1.0/24 and fd10:8912:0:11::/64
ensure_rule iptables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51421 -s 10.1.0.0/24 -j ACCEPT
ensure_rule ip6tables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51421 -s fd10:8912:0:11::/64 -j ACCEPT

# UDP 51422 only for interface bridge0  for 10.2.0/24 and fd10:8912:0:12::/64
ensure_rule iptables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51422 -s 10.2.0.0/24 -j ACCEPT
ensure_rule ip6tables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51422 -s fd10:8912:0:12::/64 -j ACCEPT

# UDP 51423 only for interface bridge0  for 10.3.0/24 and fd10:8912:0:13::/64
ensure_rule iptables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51423 -s 10.3.0.0/24 -j ACCEPT
ensure_rule ip6tables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51423 -s fd10:8912:0:13::/64 -j ACCEPT

# UDP 51424 only for interface bridge0  for 10.4.0/24 and fd10:8912:0:14::/64
ensure_rule iptables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51424 -s 10.4.0.0/24 -j ACCEPT
ensure_rule ip6tables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51424 -s fd10:8912:0:14::/64 -j ACCEPT

# UDP 51425 only for interface bridge0  for 10.5.0/24 and fd10:8912:0:15::/64
ensure_rule iptables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51425 -s 10.5.0.0/24 -j ACCEPT
ensure_rule ip6tables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51425 -s fd10:8912:0:15::/64 -j ACCEPT

# UDP 51426 only for interface bridge0  for 10.6.0/24 and fd10:8912:0:16::/64
ensure_rule iptables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51426 -s 10.6.0.0/24 -j ACCEPT
ensure_rule ip6tables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51426 -s fd10:8912:0:16::/64 -j ACCEPT

# UDP 51427 only for interface bridge0  for 10.7.0/24 and fd10:8912:0:17::/64
ensure_rule iptables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51427 -s 10.7.0.0/24 -j ACCEPT
ensure_rule ip6tables-legacy -I INPUT -i "${LAN_IF}" -p udp --dport 51427 -s fd10:8912:0:17::/64 -j ACCEPT

# bridge0  all ports all protocols from 10.89.12.0/24 and 2a01:8b81:4800:9c00::/64
ensure_rule iptables-legacy -I INPUT -i "${LAN_IF}" -s 10.89.12.0/24 -j ACCEPT
ensure_rule ip6tables-legacy -I INPUT -i "${LAN_IF}" -s 2a01:8b81:4800:9c00::/64 -j ACCEPT

# --- Connection tracking safety rules (global) ---
log "Ensuring conntrack safety rules (ESTABLISHED,RELATED)..."
ensure_rule iptables-legacy -A INPUT   -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ensure_rule iptables-legacy -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# --- WireGuard firewall rules (wg0 specific) ---
log "Ensuring WireGuard firewall rules..."
if ip link show "${WG_IF}" >/dev/null 2>&1; then
	# Allow VPN subnet traffic on wg0
	ensure_rule iptables-legacy -A INPUT   -i "${WG_IF}" -s "${VPN_SUBNET}" -j ACCEPT
	ensure_rule iptables-legacy -A FORWARD -i "${WG_IF}" -s "${VPN_SUBNET}" -j ACCEPT
	ensure_rule iptables-legacy -A FORWARD -o "${WG_IF}" -d "${VPN_SUBNET}" -j ACCEPT

	# NAT VPN traffic to LAN
	ensure_rule iptables-legacy -t nat -A POSTROUTING -s "${VPN_SUBNET}" -o "${LAN_IF}" -j MASQUERADE

	log "WireGuard firewall rules applied: VPN ${VPN_SUBNET} bridged to LAN ${LAN_SUBNET} via ${LAN_IF}."
else
	log "WARN: WireGuard interface ${WG_IF} not found, skipping WireGuard rules."
fi

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
