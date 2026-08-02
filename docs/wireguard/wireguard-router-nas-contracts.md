# WireGuard Router & NAS Contracts
Homelab Network — Router + NAS Unified Control Plane

This document defines the formal split of responsibilities, invariants, preconditions, postconditions, and failure modes for the router and NAS within the WireGuard control plane. It ensures deterministic behavior, safe multi-operator workflows, and correct IPv6/NAT66 operation.

## 1. Purpose of Router/NAS Contracts

The WireGuard control plane is intentionally split across two machines:

- Router (Asus RT‑AX86U)
- NAS (Synology / QNAP / Ugreen)

This split is governed by strict contracts that define:

- what each machine must do
- what each machine must never do
- how identity is managed
- how IPv6/NAT66 is handled
- how drift is detected
- how failures are remediated

These contracts prevent accidental misconfiguration and ensure reproducible convergence.

## 2. Router Responsibilities (Authoritative Server)

The router is the authoritative WireGuard server.

# Contract R1 — Router hosts the primary WireGuard interface
wgs1 must exist and be the server endpoint.

# Contract R2 — Router identity lives in NVRAM
wgs1_priv and wgs1_pub must be stored in NVRAM.

# Contract R3 — Router identity must never be overwritten
Repo must never push router private key.

# Contract R4 — Router must load WireGuard kernel module
router-ensure-wg-module must succeed.

# Contract R5 — Router must install firewall rules
wg-firewall.sh must be applied.

# Contract R6 — Router must provide IPv6 RA/PD
Router must advertise IPv6 prefixes to NAS.

# Contract R7 — Router must forward IPv6
IPv6 forwarding must be enabled.

# Contract R8 — Router must not perform NAT66
NAT66 must occur only on NAS.

# Contract R9 — Router must validate kernel state
wg-readiness-probe.sh must confirm no drift.

# Contract R10 — Router must install configs via wgctl.sh
Manual installation is forbidden.

# Contract R11 — Router must maintain correct routes
IPv4 and IPv6 routes must match config.

# Contract R12 — Router must expose correct public endpoint
WAN IP + port must be correct.

## 3. Router Failure Modes

# Failure F-R1 — Missing WireGuard module
Symptoms: wgs1 does not exist
Fix: make router-ensure-wg-module

# Failure F-R2 — Missing NVRAM identity
Symptoms: nvram get wgs1_priv returns empty
Fix: make router-bootstrap-wg-keys

# Failure F-R3 — Firewall missing
Symptoms: peers connect but no traffic
Fix: make wg-install-router

# Failure F-R4 — IPv6 RA/PD broken
Symptoms: NAS has no global IPv6
Fix: make wg-router-ipv6-probe

# Failure F-R5 — Kernel drift
Symptoms: wg-readiness-probe mismatch
Fix: make wg-install-router

## 4. NAS Responsibilities (Client + IPv6 Egress)

The NAS is the authoritative IPv6 egress point for WireGuard clients.

# Contract N1 — NAS hosts client interfaces
wg7, wg8, etc. must exist.

# Contract N2 — NAS identity lives in SOPS
wg7_priv, wg8_priv must be stored in encrypted YAML.

# Contract N3 — NAS must maintain global IPv6
IPv6 must be obtained via RA/PD from router.

# Contract N4 — NAS must perform NAT66
NAT66 must be applied to IPv6 egress.

# Contract N5 — NAS must maintain IPv6 default route
ip -6 route show must contain default route.

# Contract N6 — NAS must validate wg7
make wg7-validate must succeed.

# Contract N7 — NAS must install configs via wgctl.sh
Manual installation is forbidden.

# Contract N8 — NAS must maintain correct peer state
wg show must match config.

# Contract N9 — NAS must maintain correct routes
IPv4 and IPv6 routes must match config.

# Contract N10 — NAS must not advertise IPv6 prefixes
Only router may provide RA/PD.

# Contract N11 — NAS must not NAT IPv4 for WireGuard
IPv4 NAT is router responsibility.

## 5. NAS Failure Modes

# Failure F-N1 — Missing wg7
Symptoms: sudo wg show wg7 fails
Fix: make wg-install-nas

# Failure F-N2 — Missing global IPv6
Symptoms: no global IPv6 on eth0
Fix: make wg-router-ipv6-probe

# Failure F-N3 — Missing NAT66
Symptoms: IPv6 egress fails
Fix: make nft-apply

# Failure F-N4 — Missing IPv6 default route
Symptoms: IPv6 unreachable
Fix: router RA/PD issue

# Failure F-N5 — Kernel drift
Symptoms: wg-readiness-probe mismatch
Fix: make wg-install-nas

## 6. Router vs NAS Identity Split

Identity split is intentional:

Router identity:
- stored in NVRAM
- never leaves router
- never stored in repo
- never decrypted by wg-generate

NAS identity:
- stored in SOPS
- versioned in repo
- decrypted only in RAM
- regenerated only when operator changes SOPS

This ensures multi-operator safety.

## 7. IPv6/NAT66 Contract

# Contract V6-1 — Router must provide IPv6 prefix
NAS must receive IPv6 via RA/PD.

# Contract V6-2 — NAS must maintain global IPv6
IPv6 must be reachable externally.

# Contract V6-3 — NAS must apply NAT66
Only NAS may NAT IPv6.

# Contract V6-4 — Router must not NAT66
Router must forward IPv6 without NAT.

# Contract V6-5 — IPv6 egress must work
curl -6 must succeed.

## 8. Control-Plane Contract

# Contract CP1 — Router and NAS must converge independently
wg-install-router and wg-install-nas must be independent.

# Contract CP2 — Router and NAS must validate independently
router-wg-health-strict and wg7-validate must be independent.

# Contract CP3 — Router and NAS must be restarted independently
wg-up-router and wg-up-nas must be independent.

# Contract CP4 — Lifecycle must orchestrate both
wg-install, wg-up, wg-down, wg-restart must call both sides.

## 9. Operator Contract

Operators must:

- use Make targets
- never edit runtime
- never edit NVRAM
- never run wgctl.sh manually
- validate after changes
- respect dirty stamps
- commit/push TSV/SOPS changes
- pull before generating

## 10. Summary

Router contracts ensure:

- authoritative identity
- correct firewall
- correct IPv6 RA/PD
- correct routing
- correct kernel state

NAS contracts ensure:

- correct IPv6 egress
- correct NAT66
- correct peer state
- correct routes
- correct identity

Together they form a deterministic, safe, reproducible WireGuard control plane.
