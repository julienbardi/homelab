# WireGuard Firewall Deep Dive
Homelab Network — Router + NAS Unified Control Plane

This document provides a full deep dive into the firewall architecture for the WireGuard control plane. It covers router firewall rules, NAS firewall behavior, WG interface protection, IPv6 forwarding, NAT66 interactions, and failure analysis.

## 1. Purpose of Firewall Deep Dive

The firewall is critical for:

- protecting WireGuard interfaces
- ensuring correct IPv4/IPv6 forwarding
- enforcing NAT/NAT66 behavior
- preventing accidental exposure
- maintaining deterministic routing
- supporting multi-operator safety

This document formalizes firewall behavior and invariants.

## 2. Router Firewall Architecture

The router firewall is implemented via wg-firewall.sh and must enforce:

- IPv4 NAT
- IPv6 forwarding
- WireGuard interface protection
- delegated prefix routing
- LAN/WAN separation

# Router Firewall Responsibilities

# R-FW-1 — Protect wgs1
Only allowed peers may reach wgs1.

# R-FW-2 — NAT IPv4
Router must NAT IPv4 for LAN and wg7.

# R-FW-3 — Forward IPv6
Router must forward IPv6 without NAT.

# R-FW-4 — Allow delegated prefix
Router must route delegated prefix to NAS.

# R-FW-5 — Block unsolicited inbound IPv6
Router must block inbound IPv6 unless established.

# R-FW-6 — Allow WireGuard UDP port
WAN → UDP/51819 → Router must be allowed.

# R-FW-7 — Maintain LAN isolation
LAN must not expose services to WAN.

## 3. Router Firewall Chains (Conceptual)

ASCII representation:

WAN_IN:
    allow UDP/51819 → wgs1
    drop unsolicited IPv6
    allow established/related

LAN_IN:
    allow LAN → Router
    allow LAN → WAN
    drop LAN → WAN unsolicited IPv6

WG_IN:
    allow peers → wgs1
    allow wg7 delegated prefix → Router
    drop everything else

NAT:
    IPv4 masquerade
    no IPv6 NAT

FORWARD:
    allow wg7 → WAN (IPv6)
    allow wg7 → WAN (IPv4)
    allow LAN → WAN
    drop WAN → LAN

## 4. NAS Firewall Architecture

NAS firewall is simpler:

- NAT66
- IPv6 forwarding
- WireGuard interface protection
- delegated prefix routing

# NAS Firewall Responsibilities

# N-FW-1 — Protect wg7
Only WireGuard traffic should reach wg7.

# N-FW-2 — NAT66 IPv6
NAS must masquerade IPv6 egress.

# N-FW-3 — Forward IPv6
NAS must forward IPv6 to router.

# N-FW-4 — Maintain IPv6 default route
NAS must route IPv6 via router.

# N-FW-5 — Block unsolicited inbound IPv6
NAS must block inbound IPv6 unless established.

# N-FW-6 — Allow wg7 → eth0
wg7 IPv6 must be forwarded to eth0.

## 5. NAT66 Firewall Chain (NAS)

NAT66 is implemented via nftables:

table ip6 homelab_nat6 {
    chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname "eth0" masquerade
    }
}

# NAT66 Invariants

# NAT66-1 — Must apply only on NAS
# NAT66-2 — Must apply only to IPv6
# NAT66-3 — Must apply only on eth0
# NAT66-4 — Must not break delegated prefix
# NAT66-5 — Must not NAT IPv4

## 6. WireGuard Interface Protection

WireGuard interfaces must be protected on both router and NAS.

# Protection Rules

# WG-P1 — Drop all inbound traffic except WG UDP
# WG-P2 — Drop all inbound IPv6 unless established
# WG-P3 — Allow wg7 delegated prefix
# WG-P4 — Allow wg7 → NAS → Router
# WG-P5 — Drop wg7 → LAN unless explicitly allowed

## 7. IPv6 Forwarding Firewall Rules

IPv6 forwarding must be enabled on both router and NAS.

# Router IPv6 Forwarding Rules

# R-V6-FW-1 — Allow NAS → Router IPv6
# R-V6-FW-2 — Allow wg7 → Router IPv6
# R-V6-FW-3 — Allow Router → ISP IPv6
# R-V6-FW-4 — Drop unsolicited inbound IPv6

# NAS IPv6 Forwarding Rules

# N-V6-FW-1 — Allow wg7 → NAS IPv6
# N-V6-FW-2 — Allow NAS → Router IPv6
# N-V6-FW-3 — Drop unsolicited inbound IPv6

## 8. Firewall Failure Modes

# Failure FW-F1 — Missing WG UDP rule
Symptoms: peers cannot connect
Fix: make wg-install-router

# Failure FW-F2 — Missing IPv4 NAT
Symptoms: IPv4 egress fails
Fix: router NAT misconfiguration

# Failure FW-F3 — Missing IPv6 forwarding
Symptoms: NAS IPv6 unreachable
Fix: router IPv6 forwarding

# Failure FW-F4 — Missing NAT66
Symptoms: IPv6 egress fails
Fix: make nft-apply

# Failure FW-F5 — Overly permissive IPv6 inbound
Symptoms: router exposed
Fix: tighten IPv6 firewall

# Failure FW-F6 — wg7 blocked
Symptoms: wg7 IPv6 unreachable
Fix: NAS firewall misconfiguration

# Failure FW-F7 — delegated prefix blocked
Symptoms: wg7 IPv6 unreachable
Fix: router firewall misconfiguration

## 9. Firewall Validation Workflow

# Step 1 — Validate router firewall
ssh router "/jffs/scripts/wg-firewall.sh"

# Step 2 — Validate NAS NAT66
sudo nft list chain ip6 homelab_nat6 postrouting

# Step 3 — Validate IPv6 forwarding
ssh router "sysctl net.ipv6.conf.all.forwarding"
sysctl net.ipv6.conf.all.forwarding

# Step 4 — Validate WG UDP
nmap -sU -p 51819 <router WAN IP>

# Step 5 — Validate delegated prefix
ip -6 route show | grep <prefix>

# Step 6 — Validate wg7
make wg7-validate

## 10. Summary

Firewall deep dive ensures:

- correct WG protection
- correct IPv4 NAT
- correct IPv6 forwarding
- correct NAT66
- correct delegated prefix routing
- correct router/NAS separation
- deterministic behavior

This is the full firewall specification for the WireGuard control plane.
