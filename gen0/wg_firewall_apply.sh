#!/bin/bash
# ============================================================
# wg_firewall_apply.sh
# ------------------------------------------------------------
# Generation 0 script: apply WireGuard firewall rules
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Configure iptables-legacy rules for WireGuard interface
#   - Scope rules to correct interfaces (never trust source IP alone)
#   - Allow VPN subnet traffic (10.4.0.0/24)
#   - NAT traffic to LAN (10.89.12.0/24)
#   - Log degraded mode if firewall apply fails
# ============================================================

set -euo pipefail

WG_IF="wg0"
VPN_SUBNET="10.4.0.0/24"
LAN_SUBNET="10.89.12.0/24"
LAN_IF="eth0"   # adjust if NAS uses different interface

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [wg_firewall_apply] $*" | tee -a /var/log/wg_firewall_apply.log
    logger -t wg_firewall_apply "$*"
}

# --- Check WireGuard interface ---
log "Checking WireGuard interface ${WG_IF}..."
if ! ip link show ${WG_IF} >/dev/null 2>&1; then
    log "ERROR: WireGuard interface ${WG_IF} not found, continuing degraded"
fi

# --- Apply firewall rules ---
log "Applying firewall rules for WireGuard (iptables-legacy)..."

# Flush old rules (safe reset)
iptables-legacy -F
iptables-legacy -t nat -F

# Allow VPN subnet traffic
iptables-legacy -A INPUT -i ${WG_IF} -s ${VPN_SUBNET} -j ACCEPT
iptables-legacy -A FORWARD -i ${WG_IF} -s ${VPN_SUBNET} -j ACCEPT
iptables-legacy -A FORWARD -o ${WG_IF} -d ${VPN_SUBNET} -j ACCEPT

# NAT VPN traffic to LAN
iptables-legacy -t nat -A POSTROUTING -s ${VPN_SUBNET} -o ${LAN_IF} -j MASQUERADE

# Allow established/related connections
iptables-legacy -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables-legacy -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Drop everything else by default (paranoid baseline)
iptables-legacy -P INPUT DROP
iptables-legacy -P FORWARD DROP
iptables-legacy -P OUTPUT ACCEPT

log "Firewall rules applied: VPN ${VPN_SUBNET} bridged to LAN ${LAN_SUBNET} via ${LAN_IF}."

# --- Save rules ---
log "Saving firewall rules..."
iptables-legacy-save > /etc/iptables/rules.v4 || log "ERROR: Failed to save iptables rules, continuing degraded"

log "WireGuard firewall setup complete (iptables-legacy enforced)."
