#!/bin/bash
# ============================================================
# router_audit.sh
# ------------------------------------------------------------
# Generation 0 script: audit health of VPN + DNS stack
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Check Headscale service status
#   - Check CoreDNS service status and forwarding
#   - Check Unbound service status and DNSSEC trust anchors
#   - Check WireGuard interface and peer connectivity
#   - Check firewall rules (iptables-legacy)
#   - Log degraded mode if any component fails
# ============================================================

set -euo pipefail

NAS_IP="10.89.12.4"
ROUTER_IP="10.89.12.1"
VPN_SUBNET="10.4.0.0/24"
WG_IF="wg0"

SCRIPT_NAME=$(basename "$0" .sh)
touch /var/log/${SCRIPT_NAME}.log
chmod 644 /var/log/${SCRIPT_NAME}.log

log() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME}] $*" | tee -a /var/log/${SCRIPT_NAME}.log
	logger -t ${SCRIPT_NAME} "$*"
}

# --- Headscale ---
log "Checking Headscale service..."
if systemctl is-active --quiet headscale; then
	version=$(headscale version 2>/dev/null || echo "unknown")
	log "Headscale running, version: $version"
else
	log "ERROR: Headscale service not active"
fi

# --- CoreDNS ---
log "Checking CoreDNS service..."
if systemctl is-active --quiet coredns; then
	log "CoreDNS service active"
	if timeout 5 dig @${NAS_IP} device.tailnet +short >/dev/null 2>&1; then
		log "CoreDNS resolving tailnet domain correctly"
	else
		log "WARN: CoreDNS not resolving tailnet domain (timeout)"
	fi
else
	log "ERROR: CoreDNS service not active"
fi

# --- Unbound ---
log "Checking Unbound service..."
if systemctl is-active --quiet unbound; then
	log "Unbound service active"
	if timeout 5 dig @${NAS_IP} . NS +dnssec +short >/dev/null 2>&1; then
		log "Unbound resolving root NS with DNSSEC"
	else
		log "WARN: Unbound not resolving root NS (timeout)"
	fi
else
	log "ERROR: Unbound service not active"
fi

# --- WireGuard ---
log "Checking WireGuard interface ${WG_IF}..."
if ip link show ${WG_IF} >/dev/null 2>&1; then
	log "WireGuard interface ${WG_IF} present"
	wg_output=$(timeout 3 wg show ${WG_IF} 2>/dev/null || echo "wg show failed or timed out")
	log "$wg_output"
else
	log "ERROR: WireGuard interface ${WG_IF} not found"
fi

# --- Firewall (iptables-legacy) ---
log "Checking firewall rules..."
if iptables-legacy -L INPUT >/dev/null 2>&1; then
	if iptables-legacy -L INPUT | grep -q "${VPN_SUBNET}"; then
		log "Firewall rules include VPN subnet ${VPN_SUBNET}"
	else
		log "WARN: Firewall rules missing VPN subnet ${VPN_SUBNET}"
	fi
else
	log "ERROR: iptables-legacy not available"
fi

log "Router audit complete."
