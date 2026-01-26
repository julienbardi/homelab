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

## 🔐 Certificates — internal CA
- `make certs-ensure`
- `make certs-status`
- `make certs-expiry`
- `make gen-client-cert CN=...`
- ⚠️ `make certs-rotate-dangerous`

### 🚀 ACME / service certificates
- `make renew`
- `make deploy-caddy`
- `make deploy-headscale`
- `make deploy-dnsdist`

## 🌐 DNS
- `make dns-stack`
- `make dns-preflight`
- `make dns-postflight`
- `make dnsmasq-status`

## 🔐 WireGuard
- `make wg-compile`
- `make wg-apply`
- `make wg-check`
- ⚠️ `make wg-rebuild-all`

## 📦 Infrastructure
- `make install-all`
- `make uninstall-all`

---

### Notes
- All state is intent-driven; validation failures never modify deployed state.
- Scripts are never executed from the repository.
- Destructive targets are explicit and never run implicitly.
- Runtime reconciliation is gated; use `FORCE=1` only after reviewing drift.
