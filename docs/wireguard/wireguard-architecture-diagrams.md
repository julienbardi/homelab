# WireGuard Architecture Diagrams
Homelab Network — Router + NAS Unified Control Plane

This document contains ASCII diagrams illustrating the WireGuard control plane architecture, including module structure, DAG flow, router/NAS roles, IPv6/NAT66 behavior, and end‑to‑end packet flow.

## 1. Module Architecture Diagram

The six-module control plane is layered and deterministic:

                   ┌──────────────────────────┐
                   │        10_env.mk         │
                   └──────────────┬───────────┘
                                  │
                                  ▼
                   ┌──────────────────────────┐
                   │       20_inputs.mk       │
                   └──────────────┬───────────┘
                                  │
                                  ▼
                   ┌──────────────────────────┐
                   │      30_generate.mk      │
                   └──────────────┬───────────┘
                                  │
                ┌─────────────────┴──────────────────┐
                ▼                                    ▼
   ┌──────────────────────────┐        ┌──────────────────────────┐
   │       40_router.mk       │        │        50_nas.mk         │
   └──────────────┬───────────┘        └──────────────┬───────────┘
                  │                                    │
                  └──────────────────┬─────────────────┘
                                     ▼
                   ┌──────────────────────────┐
                   │      60_lifecycle.mk     │
                   └──────────────────────────┘

## 2. Target-Level DAG Diagram

Expanded DAG showing Makefile target relationships:

wg-interfaces.tsv
    ↓
wg-subnets.mk
wg-interfaces.mk
    ↓
wg-generate
    ↓
router-firewall
router-bootstrap-wg-keys
    ↓
wg-install-router
wg-install-nas
    ↓
wg-up-router
wg-up-nas
    ↓
wg-up
    ↓
wg-status

wg-down-router
wg-down-nas
    ↓
wg-down
    ↓
wg-restart

wg-clean-state
    ↓
wg-clean-out

## 3. Router Architecture Diagram

Router responsibilities:

                 ┌──────────────────────────────┐
                 │          Router (RT-AX86U)   │
                 └──────────────────────────────┘
                         │
                         │ WireGuard server (wgs1)
                         ▼
                 ┌──────────────────────────────┐
                 │  NVRAM Identity (wgs1_priv)  │
                 │  NVRAM Identity (wgs1_pub)   │
                 └──────────────────────────────┘
                         │
                         │ Firewall (wg-firewall.sh)
                         ▼
                 ┌──────────────────────────────┐
                 │ IPv6 RA/PD Provider          │
                 │ IPv6 Forwarding              │
                 │ IPv4/IPv6 Routing            │
                 └──────────────────────────────┘

## 4. NAS Architecture Diagram

NAS responsibilities:

                 ┌──────────────────────────────┐
                 │              NAS             │
                 └──────────────────────────────┘
                         │
                         │ WireGuard clients (wg7, wg8)
                         ▼
                 ┌──────────────────────────────┐
                 │  SOPS Identity (wg7_priv)    │
                 │  SOPS Identity (wg8_priv)    │
                 └──────────────────────────────┘
                         │
                         │ IPv6 global address (RA/PD)
                         ▼
                 ┌──────────────────────────────┐
                 │ NAT66 (nftables)             │
                 │ IPv6 egress                  │
                 └──────────────────────────────┘

## 5. IPv6/NAT66 Flow Diagram

End-to-end IPv6 flow from wg7 to the internet:

wg7 (NAS)
    │
    │ IPv6 packet
    ▼
NAS eth0 (global IPv6)
    │
    │ NAT66 (masquerade)
    ▼
Router (IPv6 forwarding)
    │
    │ ISP IPv6 uplink
    ▼
Internet (IPv6)

ASCII diagram:

wg7 ──► NAS ──► NAT66 ──► Router ──► ISP ──► Internet

## 6. WireGuard Packet Flow Diagram

End-to-end WG packet flow:

Client
    │ encrypted WG packet
    ▼
wg7 (NAS)
    │ decrypted packet
    ▼
NAS routing
    │
    ▼
Router (gateway)
    │
    ▼
Internet

ASCII diagram:

Client → wg7 → NAS → Router → Internet

## 7. Drift Detection Diagram

Drift detection flow:

TSV change
    │
    ▼
wg-generate
    │
    ▼
Hash drift?
    │
    ├── Yes → dirty stamps → wg-install-router / wg-install-nas
    │
    └── No → no action

Kernel drift:

wg-readiness-probe.sh
    │
    ▼
Kernel mismatch?
    │
    ├── Yes → EXECUTE_DEPLOY=1 → install
    │
    └── No → OK

## 8. Identity Architecture Diagram

Router identity:

                 ┌──────────────────────────────┐
                 │ Router NVRAM                 │
                 ├──────────────────────────────┤
                 │ wgs1_priv                    │
                 │ wgs1_pub                     │
                 └──────────────────────────────┘

