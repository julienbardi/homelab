# Homelab Make Targets

## 📑 Table of Contents
- 🧱 [Prerequisites](#-prerequisites)
- 🔐 [Security / access control](#-security--access-control)
- 🧩 [System tuning](#-system-tuning)
- 🔥 [NAS firewall — service exposure](#-nas-firewall--service-exposure)
- 🔐 [Certificates — internal CA](#-certificates--internal-ca)
- 🚀 [ACME / service certificates](#-acme--service-certificates)
- 📡 [Router certificate lifecycle](#-router-certificate-lifecycle)
- 🌐 [DNS](#-dns)
- 🌐 [DNS / DDNS](#-dns--ddns)
- 🔐 [WireGuard — lifecycle](#-wireguard--lifecycle)
- 🔐 [WireGuard — client lifecycle](#-wireguard--client-lifecycle)
- 🔍 [WireGuard — inspection (read-only)](#-wireguard--inspection-read-only)
- 📦 [Infrastructure](#-infrastructure)
- 📝 [Notes](#-notes)

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

## 📡 Router certificate lifecycle

- `make deploy-router` — Deploy ECC certificate and apply script to the router
- `make validate-router` — Validate that the router has the correct cert/key installed
- `make router-logs` — Live tail of router-side certificate apply logs
- `make bootstrap-router` — Full prepare → deploy → validate sequence

## 🌐 DNS

- `make dns-stack`
- `make dns-preflight`
- `make dns-postflight`
- `make dnsmasq-status`

## 🌐 Router DDNS (Infomaniak)

The router uses an event-driven DynDNS script compatible with Asuswrt-Merlin.
The DDNS layer is split into deployment and execution for clarity and safety.

Targets:

- `router-ddns-deploy`
  Deploys the DDNS runtime surface (`ddns-start` and secret material) to the router.
  This target is idempotent and performs no network calls.

- `router-ddns-run`
  Executes the DDNS update logic on the router. Safe to re-run; provider-level
  idempotence (`good` / `nochg`) is relied upon.

- `router-ddns`
  Convenience target that performs both deployment and execution.
  This is the default and recommended entry point.

Secrets are validated structurally via `ddns-secret-ensure` before deployment.
No cron jobs are installed; execution is event-driven by Asuswrt-Merlin.

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

## 🔍 WireGuard — inspection (read-only)

- `make wg-status` — Interface and peer summary
- `make wg-runtime` — Kernel peer state
- `make wg-dashboard` — Client ↔ interface mapping
- `make wg-clients` — Client inventory
- `make wg-intent` — Addressing and endpoint intent

## 📦 Infrastructure

- `make install-all`
- `make uninstall-all`

### Router: Access & diagnostics

- `make router-ssh-check` — Verify non‑interactive SSH access to router
- `make router-health` — Read‑only router health check
- `make router-health-strict` — Enforce strict security invariants

### Router: Bootstrap & firewall

`router-bootstrap` establishes a safe, minimal control plane on the router
(SSH access, helper scripts, DDNS, base firewall hooks) but does not expose services.

- `make router-bootstrap` — Install helpers and converge base services
- `make router-firewall` — Assert Skynet firewall enforcement
- `make router-firewall-install` — Deploy firewall hook script
- `make router-firewall-started` — Assert base firewall is running
- `make router-firewall-hardened` — Assert full firewall hardening
- `make router-firewall-audit` — Dump firewall rules and WireGuard state

### Router: Certificates (internal CA)

- `make certs-create` — Create internal CA (idempotent)
- `make certs-deploy` — Deploy certificates to router
- `make certs-ensure` — Ensure CA exists and is deployed
- `make certs-status` — Show deployed certificate status
- `make certs-expiry` — Show CA expiry date
- `make certs-rotate-dangerous` — Rotate CA (DESTRUCTIVE)
- `make router-certs-deploy` — Deploy router certificates
- `make router-certs-validate` — Validate router certificates
- `make router-certs-validate-caddy` — Validate Caddy certificates

### Router: Caddy (router edge)

- `make router-caddy-install` — Install Caddy binary on router
- `make router-caddy-config` — Push and validate Caddy configuration
- `make router-caddy` — Full Caddy deployment
- `make router-caddy-status` — Show Caddy process status
- `make router-caddy-start` — Start Caddy
- `make router-caddy-stop` — Stop Caddy

### Router: WireGuard (control plane)

- `make router-wg-deploy` — Deploy WireGuard compiler scripts to router
- `make router-wg-check` — Run WireGuard compilers on router
- `make router-wg-dump` — Run WireGuard compilers with WG_DUMP=1
- `make router-wg-preflight` — Validate router WireGuard environment

### Router orchestration (aggregates)

- `make router-all` — Converge router baseline (DDNS, dnsmasq cache, firewall started)
- `make router-all-full` — router-all + full Caddy converge (service exposure)

### 🧰 Local Developer Tools

- `make lint` — Lint Makefiles with checkmake
- `make lint-fast` — Fast linting (subset of checks)
- `make lint-all` — Full lint suite across repo
- `make lint-scripts` — Lint shell scripts
- `make lint-scripts-partial` — Lint only changed scripts
- `make lint-semantic` — Validate semantic commit messages
- `make lint-semantic-strict` — Strict semantic commit validation
- `make tools` — Install local developer tooling
- `make spellcheck` — Interactive spellcheck of Markdown files
- `make spellcheck-comments` — Spellcheck Makefile comments
- `make distclean` — Remove local tools and staged scripts
- `make clean` — Remove local build artifacts
- `make clean-soft` — Remove temporary files without touching tools

## 📝 Notes

- Router targets are split into deploy vs execute where side effects exist.
  Aggregate targets compose these explicitly.
- All state is intent-driven; validation failures never modify deployed state.
- Scripts are never executed from the repository.
- Destructive targets are explicit and never run implicitly.
- Runtime reconciliation is gated; use `FORCE=1` only after reviewing drift.
