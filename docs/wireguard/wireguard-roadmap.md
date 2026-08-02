# WireGuard Roadmap
Homelab Network — Router + NAS Unified Control Plane

This document outlines the future roadmap for the WireGuard control plane. It covers planned improvements, architectural extensions, reliability upgrades, IPv6/NAT66 enhancements, multi-router support, and long-term evolution of the system.

## 1. Purpose of the Roadmap

The WireGuard control plane is already deterministic, modular, and multi-operator safe.
This roadmap defines how it will evolve while preserving:

- reproducibility
- explicit contracts
- stable identity
- safe operator workflows
- clean Makefile DAG
- separation of repo vs runtime

## 2. Near-Term Improvements (0–3 months)

# 2.1 SOPS Key Rotation Workflow
Add a dedicated workflow for rotating WireGuard private keys:

- rotate NAS keys
- rotate peer keys
- rotate PSKs
- preserve router NVRAM identity
- ensure generation_id increments
- ensure drift detection catches mismatches

# 2.2 Peer Provisioning Automation
Introduce wg-peers.tsv as a first-class input:

- peer inventory
- peer IP assignment
- peer allowed-ips
- peer endpoint
- peer PSK
- automatic config generation

# 2.3 IPv6/NAT66 Diagnostics Expansion
Extend wg7-validate with:

- IPv6 SLAAC timing checks
- delegated prefix validation
- NAT66 rule consistency
- IPv6 MTU path checks

# 2.4 Router Firewall Contract
Formalize wg-firewall.sh contract:

- required chains
- required rules
- required NAT66 exclusions
- required IPv4/IPv6 forwarding

## 3. Mid-Term Improvements (3–9 months)

# 3.1 Multi-Router Support
Extend TSV model to support:

router1
router2

Each router would have:

- independent identity
- independent firewall
- independent WG server
- independent IPv6 RA/PD
- independent NAT66

# 3.2 Multi-NAS Support
Extend TSV model to support:

nas1
nas2

Each NAS would have:

- independent wg7/wg8 interfaces
- independent NAT66
- independent IPv6 egress
- independent peer sets

# 3.3 Dynamic Subnet Allocation
Introduce automatic subnet allocation:

- avoid manual CIDR assignment
- avoid collisions
- avoid Docker conflicts
- generate IPv4/IPv6 subnets deterministically

# 3.4 Metrics & Monitoring
Add Prometheus exporters:

- handshake age
- transfer stats
- peer availability
- IPv6 reachability
- NAT66 hit counters

# 3.5 WireGuard Event Logging
Add structured logs for:

- interface up/down
- drift detection
- identity changes
- IPv6 changes
- NAT66 changes

## 4. Long-Term Improvements (9–24 months)

# 4.1 Full IPv6-Only WireGuard
Transition to IPv6-only WG:

- remove IPv4 subnets
- remove IPv4 allowed-ips
- remove IPv4 NAT
- rely entirely on IPv6 RA/PD + NAT66

# 4.2 Multi-Site Homelab Mesh
Extend control plane to support:

- multiple physical sites
- multiple routers
- multiple NAS nodes
- automatic peer discovery
- automatic mesh routing

# 4.3 WireGuard Policy Engine
Introduce policy-based routing:

- per-peer routing
- per-interface routing
- per-subnet routing
- IPv6-only policies
- NAT66 bypass policies

# 4.4 Zero-Downtime Config Deployment
Implement atomic WG config updates:

- preflight validation
- atomic swap
- rollback on failure
- handshake preservation

# 4.5 WireGuard Identity Ledger
Introduce identity ledger:

- track identity changes
- track peer additions
- track peer removals
- track generation_id history
- track drift events

## 5. Architectural Extensions

# Extension 1 — Secrets Contract
Formalize secrets contract:

- router identity immutable
- NAS identity versioned
- peer identity versioned
- SOPS-only storage
- RAM-only decryption

# Extension 2 — Makefile DAG Contract
Formalize DAG invariants:

- 10_env.mk always first
- 20_inputs.mk always second
- 30_generate.mk always third
- router/NAS parallel
- lifecycle always last

# Extension 3 — Runtime Contract
Formalize runtime invariants:

- no manual edits
- no partial configs
- no stale configs
- no stale stamps
- no stale scripts

# Extension 4 — IPv6 Contract
Formalize IPv6 invariants:

- router RA/PD required
- NAS global IPv6 required
- NAT66 required
- IPv6 default route required

## 6. Operator Experience Improvements

# 6.1 Operator Dashboard
Add a dashboard showing:

- router WG status
- NAS WG status
- IPv6 status
- NAT66 status
- drift status
- peer status

# 6.2 Operator Notifications
Add notifications for:

- drift detected
- identity mismatch
- IPv6 failure
- NAT66 failure
- peer offline

# 6.3 Operator Safety Checks
Add preflight checks:

- TSV validation
- secrets validation
- subnet conflict detection
- Docker subnet exclusion
- IPv6 prefix validation

## 7. Documentation Improvements

# 7.1 WireGuard Glossary
Add glossary for:

- RA/PD
- NAT66
- generation_id
- dirty stamps
- drift detection
- identity contracts

# 7.2 WireGuard Examples
Add examples for:

- adding peers
- adding interfaces
- adding routers
- adding NAS nodes
- rotating keys

# 7.3 WireGuard Troubleshooting Trees
Add decision trees for:

- router issues
- NAS issues
- IPv6 issues
- NAT66 issues
- drift issues

## 8. Summary

The WireGuard roadmap focuses on:

- multi-router support
- multi-NAS support
- IPv6-only evolution
- dynamic subnet allocation
- peer provisioning
- metrics and monitoring
- zero-downtime deployment
- identity ledger
- operator dashboard
- stronger contracts

This roadmap ensures the control plane remains deterministic, extensible, and operator-safe for years to come.
