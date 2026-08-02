# WireGuard Control‑Plane Modules
Homelab Network — Router + NAS Unified Control Plane

This document describes each module in the WireGuard control plane, its responsibilities, the targets it defines, and the runtime state it interacts with. It complements architecture.md and dag.md.

## Module Overview

The control plane is split into six deterministic modules:

1. 10_env.mk — Environment, constants, stamps, sudo wrappers
2. 20_inputs.mk — TSV → MK generation (subnets + interface lists)
3. 30_generate.mk — Config generation + dirty‑stamp tracking
4. 40_router.mk — Router control plane (NVRAM, firewall, install/up/down)
5. 50_nas.mk — NAS control plane (install/up/down, wg7 validation)
6. 60_lifecycle.mk — Unified orchestration (install/up/down/restart/status)

The orchestrator mk/40_wireguard.mk includes these modules in order.

## 1. Module: 10_env.mk
Environment, constants, paths, stamps, sudo wrappers

# Responsibilities
- Define all WireGuard paths (WG_ROOT, WG_OUTPUT_ROUTER, WG_FIREWALL)
- Define persistent state stamps (wg_router_dirty.stamp, wg_nas_dirty.stamp)
- Define sudo wrapper (WG_SUDO)
- Define canonical environment block (WG_ENV)
- Define dynamic MK output paths (WG_SUBNETS_MK, WG_INTERFACE_LIST_STAMP)
- Define router interface inventory (WG_INTERFACES_ROUTER)

# Targets
None. This module only defines variables.

# Consumes
Nothing.

# Produces
Environment variables used by all other modules.

## 2. Module: 20_inputs.mk
TSV → MK generation (subnets + interface lists)

# Responsibilities
- Convert wg-interfaces.tsv into:
  - wg-subnets.mk (subnet map)
  - wg-interfaces.mk (NAS interface list)
- Load generated MK files into the DAG
- Provide dynamic variables WG_INTERFACES_NAS and subnet definitions

# Targets
- $(WG_SUBNETS_MK)
- $(WG_INTERFACE_LIST_STAMP)

# Consumes
- wireguard/input/wg-interfaces.tsv
- wg-plan-subnets.sh

# Produces
- wg-subnets.mk
- wg-interfaces.mk

## 3. Module: 30_generate.mk
Config generation + dirty‑stamp tracking

# Responsibilities
- Generate router and NAS WireGuard configs
- Compute pre‑generation and post‑generation hashes
- Detect configuration mutations
- Mark router and NAS dirty stamps
- Provide wg-clean-state

# Targets
- wg-generate
- wg-clean-state

# Consumes
- wg-subnets.mk
- wg-interfaces.mk
- router-bootstrap-wg-keys
- wg-generate-configs.sh

# Produces
- $(WG_OUTPUT_ROUTER)/*.conf
- wg_router_dirty.stamp
- wg_nas_dirty.stamp

## 4. Module: 40_router.mk
Router control plane

# Responsibilities
- Ensure WireGuard kernel module is loaded
- Ensure router NVRAM identity exists (wgs1_priv, wgs1_pub)
- Install router firewall script
- Deploy router configs
- Validate router kernel state
- Bring router interface up/down
- Provide IPv6 diagnostic probe

# Targets
- router-ensure-wg-module
- router-bootstrap-wg-keys
- router-firewall
- wg-install-router
- wg-up-router
- wg-down-router
- router-wg-health