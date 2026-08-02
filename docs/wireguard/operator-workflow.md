# WireGuard Operator Workflow
Homelab Network — Router + NAS Unified Control Plane

This document describes the deterministic operator workflow for managing the WireGuard control plane. It covers routine operations, topology changes, secrets management, drift remediation, validation, and debugging.

## 1. Operator Principles

The WireGuard control plane enforces strict multi-operator safety:

- Repo contains templates (TSVs), not authoritative configs.
- Runtime contains authoritative state under /var/lib/homelab/wireguard.
- All convergence flows through Make targets.
- Dirty stamps track when router/NAS need redeploy.
- Drift is detected explicitly; operators choose how to resolve it.
- No manual edits to runtime files.

## 2. Routine Daily Workflow

This is the standard workflow when no topology changes are needed.

# Step 1 — Update repo
git pull

# Step 2 — Generate configs
make wg-generate

# Step 3 — Install configs
make wg-install

# Step 4 — Bring up WireGuard
make wg-up

# Step 5 — Validate
make router-wg-health-strict
make wg7-validate

This ensures router and NAS converge to the correct runtime state.

## 3. Topology Change Workflow (TSV edits)

When modifying WireGuard topology (adding clients, changing subnets, etc.):

# Step 1 — Edit TSVs
Modify files under wireguard/input/*.tsv.

# Step 2 — Commit and push
git commit -am "Update WG topology"
git push

# Step 3 — Pull on homelab host
git pull

# Step 4 — Regenerate configs
make wg-generate

# Step 5 — Install updated configs
make wg-install

# Step 6 — Restart WireGuard
make wg-restart

# Step 7 — Validate
make router-wg-health-strict
make wg7-validate

## 4. Secrets Workflow (SOPS)

WireGuard private keys and PSKs are stored in SOPS-encrypted files.

# Step 1 — Edit secrets
sops wireguard/secrets/*.yaml

# Step 2 — Commit and push
git commit -am "Update WG secrets"
git push

# Step 3 — Pull on homelab host
git pull

# Step 4 — Regenerate configs
make wg-generate

# Step 5 — Install
make wg-install

# Step 6 — Restart
make wg-restart

## 5. Drift Detection & Remediation

The control plane detects drift in:

- router kernel state
- NAS kernel state
- router NVRAM identity
- generated configs
- runtime vs repo topology

Dirty stamps indicate required redeploy:

wg_router_dirty.stamp → router needs install
wg_nas_dirty.stamp → NAS needs install

# To remediate drift:

make wg-install-router
make wg-install-nas

# To fully converge:

make wg-up

## 6. Router Validation Workflow

# Check WireGuard interface
make router-wg-health-strict

# Audit router WG state
make router-wg-audit

# Probe IPv6 stack
make wg-router-ipv6-probe

This validates RA/PD, forwarding, and IPv6 readiness.

## 7. NAS Validation Workflow

# Validate wg7
make wg7-validate

This checks:

- wg7 presence
- IPv4 self-ping
- NAS global IPv6
- NAT66 rule
- IPv6 internet reachability

## 8. Full Convergence Workflow

This is the “everything must be correct” workflow.

make wg-generate
make wg-install
make wg-up
make router-wg-health-strict
make wg7-validate
make router-wg-audit

## 9. Debugging Workflow

# Router debugging
ssh router "wg show"
ssh router "ip route show table all | grep wgs1"
ssh router "nvram get wgs1_priv"
ssh router "nvram get wgs1_pub"

# NAS debugging
sudo wg show
sudo ip -6 addr show dev eth0
sudo nft list chain ip6 homelab_nat6 postrouting

# Control-plane debugging
make wg-status
make wg-install-router VERBOSE=1
make wg-install-nas VERBOSE=1

## 10. Cleanup Workflow

To remove scripts, sockets, and dirty stamps:

make wg-clean-out

This does not remove configs or keys.

## 11. Emergency Recovery Workflow

If router WireGuard is broken:

make wg-down-router
make wg-install-router
make wg-up-router

If NAS WireGuard is broken:

make wg-down-nas
make wg-install-nas
make wg-up-nas

If both are broken:

make wg-down
make wg-install
make wg-up

## 12. Summary

Operators follow deterministic workflows:

- Routine: pull → generate → install → up → validate
- Topology change: edit TSV → generate → install → restart → validate
- Secrets change: edit SOPS → generate → install → restart
- Drift remediation: install-router / install-nas
- Validation: router-wg-health-strict + wg7-validate
- Debugging: wg-status + router/NAS probes

This ensures safe, reproducible, multi-operator WireGuard management.
