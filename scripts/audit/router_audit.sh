#!/bin/bash
# ============================================================
# router_audit.sh
# ------------------------------------------------------------
# Audit health of VPN + DNS stack
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Check Headscale service status
#   - Check CoreDNS service status and forwarding
#   - Check Unbound service status and DNSSEC trust anchors
#   - Check WireGuard interfaces wg0–wg7 and tailscale0
#   - Check firewall rules (run_as_root /sbin/iptables-legacy)
#   - Log degraded mode if any component fails
# ============================================================

set -euo pipefail
source "/home/julie/src/homelab/scripts/common.sh"

NAS_IP="10.89.12.4"
VPN_SUBNET="10.4.0.0/24"

SCRIPT_NAME=$(basename "$0" .sh)
touch /var/log/${SCRIPT_NAME}.log
chmod 644 /var/log/${SCRIPT_NAME}.log

log() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME}] $*" | tee -a /var/log/${SCRIPT_NAME}.log
	logger -t ${SCRIPT_NAME} "$*"
}

# --- Headscale ---
log "🔍 Checking Headscale service..."
if systemctl is-active --quiet headscale; then
	version=$(headscale version 2>/dev/null || echo "unknown")
	log "✅ Headscale running, version: $version"
else
	log "❌ ERROR: Headscale service not active"
fi

# --- CoreDNS ---
log "🔍 Checking CoreDNS service..."
if systemctl is-active --quiet coredns; then
	log "✅ CoreDNS service active"
	if timeout 5 dig @"${NAS_IP}" device.tailnet +short >/dev/null 2>&1; then
		log "✅ CoreDNS resolving tailnet domain correctly"
	else
		log "⚠️ WARN: CoreDNS not resolving tailnet domain (timeout)"
	fi
else
	log "❌ ERROR: CoreDNS service not active"
fi

# --- Unbound ---
log "🔍 Checking Unbound service..."
if systemctl is-active --quiet unbound; then
	log "✅ Unbound service active"
	if timeout 5 dig @"${NAS_IP}" . NS +dnssec +short >/dev/null 2>&1; then
		log "✅ Unbound resolving root NS with DNSSEC"
	else
		log "⚠️ WARN: Unbound not resolving root NS (timeout)"
	fi
else
	log "❌ ERROR: Unbound service not active"
fi

# --- WireGuard + Tailscale interfaces ---
for IFACE in wg{0..7} tailscale0; do
	log "🔍 Checking interface ${IFACE}..."
	if ip link show "${IFACE}" >/dev/null 2>&1; then
		log "✅ Interface ${IFACE} present"

		if [[ "${IFACE}" == "tailscale0" ]]; then
			log "ℹ️ tailscale0 present (use 'tailscale status' for details)"
			continue
		fi

		wg_output=$(run_as_root /usr/bin/wg show "${IFACE}" 2>&1 || true)
		if echo "${wg_output}" | grep -q "peer:"; then
			log "✅ ${IFACE} has peers configured:"
			log "${wg_output}"
		else
			log "⚠️ ${IFACE} present but no peers configured"
		fi
	else
		log "⚠️ WARN: Interface ${IFACE} not found"
	fi
done

# --- Firewall (run_as_root /sbin/iptables-legacy) ---
log "🔍 Checking firewall rules..."
if run_as_root /sbin/iptables-legacy -L INPUT >/dev/null 2>&1; then
	if run_as_root /sbin/iptables-legacy -L INPUT | grep -q "${VPN_SUBNET}"; then
		log "✅ Firewall rules include VPN subnet ${VPN_SUBNET}"
	else
		log "⚠️ WARN: Firewall rules missing VPN subnet ${VPN_SUBNET}"
	fi
else
	log "❌ ERROR: run_as_root /sbin/iptables-legacy not available"
fi

log "🏁 Router audit complete."
