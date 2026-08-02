# WireGuard Control‑Plane Dependency Graph
Homelab Network — Router + NAS Unified Control Plane

This document describes the full dependency graph (DAG) of the WireGuard control plane. It shows how modules depend on each other, how targets flow, and how runtime state propagates through the system.

## 1. Module-Level DAG

The six modules form a deterministic layered architecture:

10_env.mk
    ↓
20_inputs.mk
    ↓
30_generate.mk
    ↓
40_router.mk   ← parallel branch
50_nas.mk      ← parallel branch
    ↓
60_lifecycle.mk

This ensures:
- environment is defined first
- inputs are processed second
- generation happens third
- router and NAS install/up/down run independently
- lifecycle orchestrates everything

## 2. Target-Level DAG

Below is the expanded DAG showing Makefile targets and their dependencies.

# 2.1 Input Processing

wg-subnets.mk:
    depends on wg-interfaces.tsv
    depends on wg-plan-subnets.sh

wg-interfaces.mk:
    depends on wg-interfaces.tsv

Both are included into the DAG.

# 2.2 Generation

wg-generate:
    depends on wg-subnets.mk
    depends on wg-interfaces.mk
    depends on router-bootstrap-wg-keys
    depends on wg-generate-configs.sh
    produces router configs
    produces dirty stamps

wg-clean-state:
    removes wg-subnets.mk and dirty stamps

# 2.3 Router Control Plane

router-ensure-wg-module:
    loads kernel module via SSH

router-bootstrap-wg-keys:
    ensures NVRAM identity exists

router-firewall:
    installs wg-firewall.sh on router

wg-install-router:
    depends on wg-generate
    depends on router-firewall
    validates kernel state via wg-readiness-probe.sh
    installs configs via wgctl.sh

wg-up-router:
    depends on wg-install-router

wg-down-router:
    calls wgctl.sh router down

router-wg-health-strict:
    checks wgs1 presence

router-wg-audit:
    dumps wg show and routing table

wg-router-ipv6-probe:
    checks IPv6 stack, RA/PD, forwarding

# 2.4 NAS Control Plane

wg-install-nas:
    depends on wg-generate
    validates kernel state via wg-readiness-probe.sh
    installs configs via wgctl.sh

wg-up-nas:
    depends on wg-install-nas

wg-down-nas:
    calls wgctl.sh nas down

wg7-validate:
    validates wg7 IPv4/IPv6/NAT66 path

# 2.5 Lifecycle

wg-install:
    depends on wg-install-router
    depends on wg-install-nas

wg-up:
    depends on wg-up-router
    depends on wg-up-nas

wg-down:
    depends on wg-down-router
    depends on wg-down-nas

wg-restart:
    depends on wg-down
    depends on wg-up

wg-status:
    calls wgctl.sh router status
    calls wgctl.sh nas status

wg-clean-out:
    depends on wg-down-router
    depends on wg-down-nas
    depends on wg-clean-state
    removes scripts and SSH sockets

## 3. ASCII Graph (Full DAG)

Below is the complete ASCII DAG showing module and target relationships.

# 3.1 Module Graph

                   ┌──────────────────────────┐
                   │   10_env.mk              │
                   └──────────────┬───────────┘
                                  │
                                  ▼
                   ┌──────────────────────────┐
                   │   20_inputs.mk           │
                   └──────────────┬───────────┘
                                  │
                                  ▼
                   ┌──────────────────────────┐
                   │   30_generate.mk         │
                   └──────────────┬───────────┘
                                  │
                ┌─────────────────┴──────────────────┐
                ▼                                    ▼
   ┌──────────────────────────┐        ┌──────────────────────────┐
   │   40_router.mk           │        │   50_nas.mk              │
   └──────────────┬───────────┘        └──────────────┬───────────┘
                  │                                    │
                  └──────────────────┬─────────────────┘
                                     ▼
                   ┌──────────────────────────┐
                   │   60_lifecycle.mk        │
                   └──────────────────────────┘

# 3.2 Target Graph (Expanded)

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

## 4. Runtime State Flow

# Inputs → MK
TSV files are converted into dynamic MK files.

# MK → Generation
wg-generate produces configs and dirty stamps.

# Generation → Router/NAS Install
Router and NAS install configs independently.

# Install → Lifecycle
Lifecycle targets orchestrate full convergence.

## 5. Dirty Stamp Propagation

Dirty stamps ensure multi-operator safety:

wg_router_dirty.stamp:
    created when router configs change
    consumed by wg-install-router

wg_nas_dirty.stamp:
    created when NAS configs change
    consumed by wg-install-nas

This prevents silent overwrites and ensures deterministic convergence.

## 6. Summary

The WireGuard control plane DAG ensures:

- deterministic ordering
- clean separation of router/NAS logic
- safe multi-operator workflows
- explicit drift detection
- reproducible convergence

This DAG is the authoritative reference for understanding how WireGuard is orchestrated in the homelab.
