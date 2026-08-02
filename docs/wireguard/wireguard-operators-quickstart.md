# WireGuard Operators Quickstart
Homelab Network — Router + NAS Unified Control Plane

This quickstart is the shortest, most practical guide for any operator who needs to manage the WireGuard control plane. It contains only the essential commands and workflows, without deep explanations.

## 1. Daily Workflow (Most Common)

# Step 1 — Update repo
git pull

# Step 2 — Generate configs
make wg-generate

# Step 3 — Install configs
make wg-install

# Step 4 — Bring WireGuard up
make wg-up

# Step 5 — Validate
make router-wg-health-strict
make wg7-validate

This is the standard daily routine.

## 2. Topology Change Workflow (TSV edits)

# Step 1 — Edit TSVs
wireguard/input/*.tsv

# Step 2 — Commit + push
git commit -am "Update WG topology"
git push

# Step 3 — Pull on homelab host
git pull

# Step 4 — Regenerate
make wg-generate

# Step 5 — Install
make wg-install

# Step 6 — Restart
make wg-restart

# Step 7 — Validate
make router-wg-health-strict
make wg7-validate

## 3. Secrets Change Workflow (SOPS)

# Step 1 — Edit secrets
sops wireguard/secrets/*.yaml

# Step 2 — Commit + push
git commit -am "Update WG secrets"
git push

# Step 3 — Pull
git pull

# Step 4 — Regenerate
make wg-generate

# Step 5 — Install
make wg-install

# Step 6 — Restart
make wg-restart

## 4. Router Commands (Quick Reference)

# Check router WG
ssh router "wg show wgs1"

# Check router identity
ssh router "nvram get wgs1_priv"
ssh router "nvram get wgs1_pub"

# Install router configs
make wg-install-router

# Bring router WG up
make wg-up-router

# Bring router WG down
make wg-down-router

# Validate router
make router-wg-health-strict

# IPv6 probe
make wg-router-ipv6-probe

## 5. NAS Commands (Quick Reference)

# Check NAS WG
sudo wg show wg7

# Install NAS configs
make wg-install-nas

# Bring NAS WG up
make wg-up-nas

# Bring NAS WG down
make wg-down-nas

# Validate wg7
make wg7-validate

# Check NAT66
sudo nft list chain ip6 homelab_nat6 postrouting

## 6. IPv6 / NAT66 Quick Checks

# Check NAS IPv6
sudo ip -6 addr show dev eth0

# Check IPv6 default route
ip -6 route show | grep default

# Check IPv6 egress
curl -6 https://ifconfig.io

## 7. Drift Quick Fixes

# Check dirty stamps
ls /var/lib/homelab/wireguard/*.stamp

# Fix router drift
make wg-install-router

# Fix NAS drift
make wg-install-nas

# Full convergence
make wg-up

## 8. Emergency Recovery

# Router broken
make wg-down-router
make router-bootstrap-wg-keys
make wg-install-router
make wg-up-router

# NAS broken
make wg-down-nas
make wg-install-nas
make wg-up-nas

# Everything broken
make wg-down
make wg-install
make wg-up

## 9. Absolute Rules (Do Not Break)

# Rule 1 — Never edit runtime files
/var/lib/homelab/wireguard is authoritative.

# Rule 2 — Never edit router NVRAM manually
Only router-bootstrap-wg-keys may modify identity.

# Rule 3 — Never run wgctl.sh directly
Always use Make targets.

# Rule 4 — Never store private keys unencrypted
Only SOPS files may contain secrets.

# Rule 5 — Never bypass drift detection
Dirty stamps must be respected.

## 10. Summary

This quickstart provides the fastest path to:

- daily operation
- topology changes
- secrets changes
- router/NAS commands
- IPv6/NAT66 checks
- drift remediation
- emergency recovery

It is the minimal operator guide for the WireGuard control plane.
