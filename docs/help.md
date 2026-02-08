# Homelab Make Targets

## 🧱 Prerequisites
- `make prereqs` — Install and verify core system prerequisites
- `make deps` — Install common build and runtime dependencies
- `make apt-update` — Force refresh apt cache (normally cached)

## 🔐 Security / access control
- `make harden-groups` — Verify group membership invariants (read-only)
- `make enforce-groups` — Enforce group membership (authorized admin only)
- `make check-groups` — Inspect group memberships

## 🧩 System tuning
- `make install-homelab-sysctl` — Install and apply homelab sysctl forwarding config
- `make net-tunnel-preflight` — Ensure NIC offload settings for UDP tunnels

## 🔥 NAS firewall — service exposure
- `make firewall-nas` — Allow trusted tunnel subnets (e.g. router‑terminated WireGuard)
  to access NAS services (bootstrap invariant)

## 🔐 Certificates — internal CA
- `make certs-ensure`
- `make certs-status`
- `make certs-expiry`
- `make gen-client-cert CN=...`
- ⚠️ `make certs-rotate-dangerous`

## 🚀 ACME / service certificates
- `make renew`
- `make deploy-caddy`
- `make deploy-headscale`
- `make deploy-dnsdist`

## 🌐 DNS
- `make dns-stack`
- `make dns-preflight`
- `make dns-postflight`
- `make dnsmasq-status`

## 🔐 WireGuard — lifecycle
- `make wg-install-scripts` — Install WireGuard operational scripts
- `make wg` — Compile, deploy, apply, and verify WireGuard state
- `make wg-compile` — Compile intent and keys
- `make wg-apply` — Apply rendered configuration to runtime
- `make wg-check` — Validate rendered and runtime state
- ⚠️ `make wg-rebuild-all` — Full destructive rebuild

## 🔐 WireGuard — client lifecycle
- `make wg-rotate-client base=<base> iface=<iface>` — Rotate client key (revokes old key)
- `make wg-remove-client base=<base> iface=<iface>` — Permanently remove client

## 🔐 WireGuard — inspection (read-only)
- `make wg-status` — Interface and peer summary
- `make wg-runtime` — Kernel peer state
- `make wg-dashboard` — Client ↔ interface mapping
- `make wg-clients` — Client inventory
- `make wg-intent` — Addressing and endpoint intent

## 📦 Infrastructure
- `make install-all`
- `make uninstall-all`

## Notes
- All state is intent-driven; validation failures never modify deployed state.
- Scripts are never executed from the repository.
- Destructive targets are explicit and never run implicitly.
- Runtime reconciliation is gated; use `FORCE=1` only after reviewing drift.
