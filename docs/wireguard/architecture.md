# WireGuard Control‑Plane Architecture
Homelab Network — Router + NAS Unified Control Plane

## 1. Purpose of the WireGuard Control Plane

The homelab WireGuard system is a deterministic control plane that:

- Generates WireGuard configurations for router and NAS
- Ensures cryptographic identity consistency
- Deploys configs safely across SSH
- Detects drift between generation, runtime, and kernel state
- Brings interfaces up/down predictably
- Supports multi‑operator workflows without overwriting each other
- Maintains authoritative runtime state under /var/lib/homelab/wireguard

The Makefile orchestrates the lifecycle; operational logic lives in wgctl.sh.

## 2. High‑Level Architecture

The WireGuard control plane is split into six modules:

1. [Environment](ca://s?q=Show_10_env_mk) — constants, paths, stamps, sudo wrappers
2. [Inputs](ca://s?q=Show_20_inputs_mk) — TSV → MK generation
3. [Generation](ca://s?q=Show_30_generate_mk) — config generation + dirty‑stamp tracking
4. [Router](ca://s?q=Show_40_router_mk) — router control plane
5. [NAS](ca://s?q=Show_50_nas_mk) — NAS control plane
6. [Lifecycle](ca://s?q=Show_60_lifecycle_mk) — unified orchestration

The orchestrator mk/40_wireguard.mk contains only include statements.

## 3. Runtime vs Repo Model

# Repo = templates
Stored under wireguard/input/*.tsv
Contains topology, interface definitions, client assignments.
Contains no secrets.

# Runtime = authoritative state
Stored under /var/lib/homelab/wireguard
Contains generated configs, dynamic subnet maps, interface lists, dirty stamps.
Operators never edit runtime manually.

# Secrets = SOPS
WireGuard private keys and PSKs live in encrypted SOPS files.

## 4. Multi‑Operator Safety Model

Multiple operators may run the homelab from different repo copies.
To prevent accidental overwrites, the control plane enforces:

# Invariant 1 — Repo is templates
# Invariant 2 — Runtime is authoritative
# Invariant 3 — Dirty stamps track mutations
# Invariant 4 — Drift detection is explicit
# Invariant 5 — All convergence flows through Make

## 5. Control‑Plane Data Flow

# 1. Inputs → MK
TSV files → wg-subnets.mk and wg-interfaces.mk

# 2. MK → Config Generation
wg-generate produces router and NAS configs + dirty stamps

# 3. Generation → Router/NAS Install
Router: NVRAM identity, firewall, config install
NAS: config install, wg7 validation

# 4. Install → Lifecycle
wg-install, wg-up, wg-down, wg-restart, wg-status

## 6. Router vs NAS Roles

# Router
- Hosts WireGuard server (wgs1)
- Stores identity in NVRAM
- Applies firewall rules
- Provides IPv6 RA/PD
- Acts as IPv4/IPv6 gateway

# NAS
- Hosts client interfaces (wg7)
- Performs NAT66
- Validates IPv6 reachability
- Acts as WireGuard hub for internal services

## 7. Drift Detection & Remediation

The control plane detects drift in:

- generated configs
- router kernel state
- NAS kernel state
- router NVRAM identity
- runtime vs repo TSVs

Operators remediate via:

- [sync repo → runtime](ca://s?q=Sync_repo_to_runtime)
- [sync runtime → repo](ca://s?q=Sync_runtime_to_repo)
- [wg-install-router](ca://s?q=wg-install-router)
- [wg-install-nas](ca://s?q=wg-install-nas)

## 8. Operator Workflow (Summary)

1. Modify TSVs in repo
2. Commit + push
3. On homelab host:
   - git pull
   - make wg-generate
   - make wg-install
   - make wg-up
4. Validate:
   - make router-wg-health-strict
   - make wg7-validate

Operators never touch runtime files manually.

## 9. Why This Architecture Works

- Deterministic
- Multi‑operator safe
- Secrets isolated
- Router/NAS split clean
- Drift detectable
- Runtime authoritative
- Repo versioned
- Makefile DAG explicit
- No hidden state
- No silent overwrites

This is a professional‑grade WireGuard control plane.
