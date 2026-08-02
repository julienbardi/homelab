# WireGuard Advanced Internals
Homelab Network — Router + NAS Unified Control Plane

This document describes the deep internals of the WireGuard control plane: generation contracts, kernel invariants, NVRAM rules, IPv6/NAT66 behavior, drift detection mechanics, and future extension points. It is intended for advanced operators and maintainers.

## 1. Generation Contracts

The WireGuard control plane enforces strict generation contracts to ensure deterministic behavior.

# Contract 1 — TSVs define topology
TSVs are authoritative templates. They define:
- interface inventory
- roles (router vs nas)
- IPv4/IPv6 subnets
- generation_id
- peer assignments (optional)

TSVs contain no secrets.

# Contract 2 — SOPS defines identity
SOPS-encrypted YAML files define:
- private keys
- PSKs
- peer identity material

Secrets are decrypted only in RAM.

# Contract 3 — wg-generate is the single source of truth
wg-generate:
- decrypts secrets
- loads TSVs
- computes subnet maps
- computes interface lists
- generates configs
- computes generation hashes
- sets dirty stamps

No other target may generate configs.

# Contract 4 — generation_id must match runtime
Each config contains:
WG_GENERATION: <id>

This must match the TSV generation_id.

# Contract 5 — configs must be immutable
Generated configs under /var/lib/homelab/wireguard/output/ must never be edited manually.

## 2. Kernel Invariants

The control plane assumes the following kernel invariants.

# Invariant 1 — WireGuard module must be loaded
router-ensure-wg-module ensures:
modprobe wireguard

# Invariant 2 — interface must exist before routes
wgctl.sh ensures:
ip link add dev <iface> type wireguard

# Invariant 3 — IPv4 routes must match config
ip route show table all | grep <iface>

# Invariant 4 — IPv6 routes must match config
ip -6 route show | grep <iface>

# Invariant 5 — NAT66 must be applied on NAS
nft list chain ip6 homelab_nat6 postrouting

# Invariant 6 — RA/PD must be functional on router
ip -6 addr show scope global

## 3. NVRAM Identity Rules (Router)

Router identity is stored in NVRAM:

wgs1_priv
wgs1_pub

# Rule 1 — Router identity is authoritative
It must never be overwritten by repo.

# Rule 2 — Identity must exist before generation
wg-generate depends on router-bootstrap-wg-keys.

# Rule 3 — Identity must persist across reboots
NVRAM commit ensures persistence.

# Rule 4 — Identity must not be regenerated unless empty
Regeneration only occurs if NVRAM is blank.

# Rule 5 — Identity must not be exported to repo
Private key must never leave router.

## 4. NAS Identity Rules

NAS identity is stored in SOPS.

# Rule 1 — NAS identity is versioned
Stored in wireguard/secrets/wg-identities.yaml.

# Rule 2 — NAS identity is decrypted only in RAM
wg-generate loads private keys into environment variables.

# Rule 3 — NAS identity must be stable
Regeneration only occurs when topology changes.

# Rule 4 — NAS identity must not be overwritten by runtime
Runtime configs are authoritative only for router.

## 5. IPv6 Internals

IPv6 behavior is critical for wg7 and NAT66.

# 5.1 Router IPv6 Responsibilities
- Provide RA/PD to NAS
- Maintain global IPv6 address
- Maintain delegated prefix
- Ensure forwarding is enabled

# 5.2 NAS IPv6 Responsibilities
- Accept RA/PD
- Maintain global IPv6 address
- Provide NAT66 for wg7
- Maintain IPv6 default route

# 5.3 NAT66 Behavior
NAT66 is implemented via nftables:

table ip6 homelab_nat6
chain postrouting
    type nat hook postrouting priority srcnat
    oifname "eth0" masquerade

# 5.4 IPv6 Egress Path
wg7 → NAS → NAT66 → router → ISP → internet

## 6. Drift Detection Internals

Drift detection is one of the most important advanced features.

# 6.1 Hash Drift
wg-generate computes:
- pre-generation hash
- post-generation hash

If different:
- router dirty stamp set
- NAS dirty stamp set

# 6.2 Kernel Drift
wg-readiness-probe.sh checks:
- interface presence
- generation_id match
- allowed-ips match
- endpoint match

If mismatch:
EXECUTE_DEPLOY=1

# 6.3 NVRAM Drift
router-bootstrap-wg-keys checks:
- wgs1_priv
- wgs1_pub

If missing:
identity regenerated

# 6.4 IPv6 Drift
wg-router-ipv6-probe checks:
- global IPv6 presence
- forwarding
- RA/PD
- wgs1 IPv6

## 7. Control-Plane Internals

# 7.1 wgctl.sh
This script performs:
- install-up
- up
- down
- status

It is the authoritative runtime operator.

# 7.2 wg-readiness-probe.sh
Validates kernel state against config.

# 7.3 wg-generate-configs.sh
Generates configs using:
- TSVs
- SOPS secrets
- subnet maps
- interface lists

# 7.4 wg-firewall.sh
Applies router firewall rules.

## 8. Future Extensions

The architecture supports future extensions without breaking invari