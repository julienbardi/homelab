# WireGuard Debugging Guide
Homelab Network — Router + NAS Unified Control Plane

This document provides a deterministic debugging workflow for the WireGuard control plane. It covers router debugging, NAS debugging, IPv6/NAT66 issues, wg7 validation, kernel drift, and control-plane troubleshooting.

## 1. Principles of Debugging

The WireGuard control plane is deterministic. Debugging follows these principles:

- Always validate router and NAS independently.
- Always check kernel state before config state.
- Always check IPv6 before NAT66.
- Always check wg7 before peers.
- Never modify runtime files manually.
- Never regenerate keys unless topology changes.
- Always converge via Make targets.

## 2. Router Debugging

The router hosts the WireGuard server (wgs1). Most issues originate here.

# 2.1 Check interface presence

ssh router "wg show wgs1"

If missing:
- router kernel module may not be loaded
- router identity may be missing
- router configs may not be installed

Fix:
make router-ensure-wg-module
make router-bootstrap-wg-keys
make wg-install-router
make wg-up-router

# 2.2 Check routing table

ssh router "ip route show table all | grep wgs1"

Look for:
- correct WG subnet routes
- no conflicting routes
- no missing default routes

# 2.3 Check NVRAM identity

ssh router "nvram get wgs1_priv"
ssh router "nvram get wgs1_pub"

If empty:
make router-bootstrap-wg-keys

# 2.4 Check firewall

ssh router "/jffs/scripts/wg-firewall.sh"

Look for:
- iptables rules applied
- no errors
- no missing chains

# 2.5 Check IPv6 stack

make wg-router-ipv6-probe

Validates:
- RA/PD
- forwarding
- global IPv6
- wgs1 IPv6

## 3. NAS Debugging

The NAS hosts client interfaces (wg7, wg8, etc.) and performs NAT66.

# 3.1 Check interface presence

sudo wg show wg7

If missing:
make wg-install-nas
make wg-up-nas

# 3.2 Check IPv4 self-ping

wg7_ip=$(sudo wg show wg7 | awk '/address/{print $2}' | cut -d/ -f1)
ping -c2 -W2 "$wg7_ip"

If fails:
- interface may be up but unconfigured
- config may not be installed

# 3.3 Check NAS global IPv6

sudo ip -6 addr show dev eth0 scope global

If missing:
- router RA/PD not working
- router IPv6 disabled
- router prefix delegation broken

# 3.4 Check NAT66

sudo nft list chain ip6 homelab_nat6 postrouting

Look for:
masquerade

If missing:
make nft-apply
make nft-confirm

# 3.5 Check IPv6 internet reachability

curl -6 --max-time 5 https://ifconfig.io

If fails:
- no global IPv6
- no default IPv6 route
- NAT66 broken

## 4. wg7 Deep Debugging

wg7 is the NAS-terminated interface used for IPv6 egress.

# 4.1 Validate wg7 end-to-end

make wg7-validate

Checks:
- interface presence
- IPv4 self-ping
- NAS global IPv6
- NAT66 rule
- IPv6 internet reachability

# 4.2 Check wg7 routes

ip -6 route show | grep wg7

Look for:
- correct subnet route
- no missing default route

# 4.3 Check wg7 peer state

sudo wg show wg7

Look for:
- latest handshake
- correct endpoint
- correct allowed-ips

## 5. Kernel Drift Debugging

Kernel drift occurs when:

- interface exists but config does not match
- config exists but kernel state differs
- generation_id mismatch
- dirty stamps present

# 5.1 Check dirty stamps

ls /var/lib/homelab/wireguard/*.stamp

If present:
make wg-install-router
make wg-install-nas

# 5.2 Check readiness probe

make wg-install-router VERBOSE=1
make wg-install-nas VERBOSE=1

Look for:
"Kernel link drift verified"

# 5.3 Check generation_id

grep WG_GENERATION /var/lib/homelab/wireguard/output/router/*.conf

Compare with TSV.

## 6. Control-Plane Debugging

# 6.1 Check status

make wg-status

Shows:
- router status
- NAS status