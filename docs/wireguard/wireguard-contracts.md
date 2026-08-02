# WireGuard Contracts
Homelab Network — Router + NAS Unified Control Plane

This document defines the formal contracts that govern the WireGuard control plane. These contracts specify invariants, preconditions, postconditions, operator guarantees, and safety rules. They ensure deterministic behavior, multi-operator safety, and long-term maintainability.

## 1. Purpose of Contracts

The WireGuard control plane is built on explicit contracts.
Contracts ensure:

- deterministic generation
- stable identity
- safe multi-operator workflows
- correct kernel state
- correct IPv6/NAT66 behavior
- reproducible convergence
- no hidden assumptions

Contracts are binding rules for both operators and the control plane.

## 2. Repo Contracts

# Contract R1 — Repo contains templates, not authoritative configs
TSVs define topology.
SOPS files define identity.
Repo never contains generated configs.

# Contract R2 — Repo must never contain private keys unencrypted
All secrets must be stored in SOPS-encrypted YAML files.

# Contract R3 — Repo must never contain router private key
Router private key lives only in NVRAM.

# Contract R4 — Repo changes must be versioned
Operators must commit and push TSV/SOPS changes.

# Contract R5 — Repo must not contain runtime state
No files from /var/lib/homelab/wireguard may appear in Git.

## 3. Runtime Contracts

# Contract RT1 — Runtime is authoritative
Generated configs under /var/lib/homelab/wireguard are authoritative.

# Contract RT2 — Runtime must not be edited manually
Operators must never modify runtime files.

# Contract RT3 — Runtime must contain complete configs
Partial configs are forbidden.

# Contract RT4 — Runtime must contain correct generation_id
generation_id in configs must match TSV.

# Contract RT5 — Runtime must contain correct identity
NAS identity must match SOPS.
Router identity must match NVRAM.

# Contract RT6 — Runtime must contain correct dirty stamps
Dirty stamps must reflect generation changes.

## 4. Identity Contracts

# Contract I1 — Router identity is immutable
Router private key must never be overwritten by repo.

# Contract I2 — Router identity must exist before generation
wg-generate depends on router-bootstrap-wg-keys.

# Contract I3 — Router identity must persist across reboots
Stored in NVRAM.

# Contract I4 — NAS identity is versioned
Stored in SOPS.

# Contract I5 — NAS identity must not be regenerated unless topology changes
Regeneration only occurs when operator updates SOPS.

# Contract I6 — Peer identity must be stable
Peer private keys must not change unless operator rotates them.

# Contract I7 — Secrets must be decrypted only in RAM
wg-generate must not write decrypted secrets to disk.

## 5. Generation Contracts

# Contract G1 — wg-generate is the only generator
No other target may generate configs.

# Contract G2 — wg-generate must load TSVs
TSVs define topology.

# Contract G3 — wg-generate must load SOPS secrets
Secrets define identity.

# Contract G4 — wg-generate must compute subnet maps
Subnet maps must match TSV.

# Contract G5 — wg-generate must compute interface lists
Interface lists must match TSV.

# Contract G6 — wg-generate must compute generation hashes
Hash drift must set dirty stamps.

# Contract G7 — wg-generate must produce complete configs
Partial configs are forbidden.

# Contract G8 — wg-generate must not write secrets to disk
Secrets must remain RAM-only.

## 6. Router Contracts

# Contract Rtr1 — Router must load WireGuard kernel module
router-ensure-wg-module must succeed.

# Contract Rtr2 — Router must have valid identity
wgs1_priv and wgs1_pub must exist.

# Contract Rtr3 — Router must install firewall rules
wg-firewall.sh must be applied.

# Contract Rtr4 — Router must install configs via wgctl.sh
Manual installation is forbidden.

# Contract Rtr5 — Router must validate kernel state
wg-readiness-probe.sh must confirm no drift.

# Contract Rtr6 — Router must maintain IPv6 RA/PD
IPv6 must be functional.

# Contract Rtr7 — Router must maintain NAT66 exclusions
Router must not NAT66 WG traffic.

## 7. NAS Contracts

# Contract NAS1 — NAS must install configs via wgctl.sh
Manual installation is forbidden.

# Contract NAS2 — NAS must maintain IPv6 global address
IPv6 must be functional.

# Contract NAS3 — NAS must maintain NAT66
NAT66 must be applied to wg7.

# Contract NAS4 — NAS must validate wg7
wg7-validate must succeed.

# Contract NAS5 — NAS must maintain correct peer state
wg show must match config.

# Contract NAS6 — NAS must maintain correct routes
IPv4 and IPv6 routes must match config.

## 8. IPv6 Contracts

# Contract V6-1 — Router must provide RA/PD
NAS must receive IPv6 prefix.

# Contract V6-2 — NAS must maintain global IPv6
IPv6 must be reachable.

# Contract V6-3 — NAT66 must be applied
NAS must masquerade IPv6 egress.

# Contract V6-4 — IPv6 default route must exist
NAS must have IPv6 default route.

# Contract V6-5 — IPv6 egress must work
curl -6 must succeed.

## 9. Drift Contracts

# Contract D1 — Hash drift must set dirty stamps
Dirty stamps must reflect config changes.

# Contract D2 — Kernel drift must trigger redeploy
wg-readiness-probe.sh must detect mismatches.

# Contract D3 — NVRAM drift must regenerate identity
Missing router identity must be regenerated.

# Contract D4 — IPv6 drift must be detected
wg-router-ipv6-probe must detect IPv6 issues.

# Contract D5 — Drift must be remediated via Make targets
Manual remediation is forbidden.

## 10. Operator Contracts

# Contract OP1 — Operators must use Make targets
Manual script execution is forbidden.

# Contract OP2 — Operators must not edit runtime
Runtime is authoritative.

# Contract OP3 — Operators must not edit NVRAM
Only router-bootstrap-wg-keys may modify identity.

# Contract OP4 — Operators must validate after changes
router-wg-health-strict and wg7-validate must be run.

# Contract OP5 — Operators must commit and push changes
TSV and SOPS changes must be versioned.

# Contract OP6 — Operators must pull before generating
Local repo must be up-to-date.

# Contract OP7 — Operators must not