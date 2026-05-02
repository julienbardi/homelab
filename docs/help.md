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
- 🌐 [Router DDNS](#-router-ddns)
- 📦 [Infrastructure](#-infrastructure)
- 💻 [Code‑server](#-codeserver)
- 📝 [Notes](#-notes)

## 🧱 Prerequisites

- `make prereqs` — Install and verify core system prerequisites
- `make deps` — Install common build and runtime dependencies
- `make apt-update` — Force refresh apt cache (normally cached)
- `make rust-system` — Install or show Rust system-wide (uses root rustup; symlinks /root/.cargo/bin/{cargo,rustc} into $(INSTALL_PATH)). Use `FORCE=1` to force reinstall.
- `make rust-system-uninstall` — Reversible uninstall: moves system rustup/cargo/rustc aside for rollback.

## 🔐 Security / access control

- `make harden-groups` — Verify group membership invariants (read-only)
- `make enforce-groups` — Enforce group membership (authorized admin only)
- `make check-groups` — Inspect group memberships

## 🧩 System tuning

- `make sysctl-preflight` — Validates system dependencies, source file existence. Run as a guard for all other sysctl targets.
- `make sysctl-inspect` — Read-only audit of current IPv6 identities.
  - IID Mapping: Displays the 64-bit Interface Identifier for every global and ULA prefix.
  - Live State: Filters out "tentative" or "deprecated" addresses to show exactly what the kernel is using for active traffic.
  - `make install-homelab-sysctl` — Reconciles the system-level forwarding rules with the repository source.
    - Functional Diffing: Uses a strip-diff engine to ignore local secrets and comments.
    - Hardware Aware: Only injects stable_secret for active interfaces (e.g., eth0, eth1).
    - Post-Apply Validation: Queries the kernel via sysctl -n to verify the state was actually accepted.
    - Idempotent Reporting: Summarizes changes (Config update / Secret injection / NOP).
  - `make rotate-ipv6-secrets` — Destructive/Identity Rotation.
  - Surgically removes existing IPv6 Stable Secrets and generates new 128-bit cryptographic identifiers.
  - Privacy: Rotates the RFC 7217 Interface Identifier (IID).
  - Side Effect: Triggers a 5-second countdown followed by a hard reboot to enforce kernel regeneration of IPv6 addresses.
  - ⚠️ Note: This will change your NAS's IPv6 addresses (GUA and ULA). Firewall rules on the router or external peers may need updating.
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

### Unbound (recursive resolver)
- `make enable-unbound`
- `make deploy-unbound`
- `make unbound-status`
- `make dns-runtime`
- `make dns`
- `make dns-reset`
- `make dns-reset-clean`
- `make dns-bench`
- `make dns-watch`
- `make dns-health`
- `make dns-runtime-check`
- `make setup-unbound-control`
- `make reset-unbound-control`

### dnsmasq (local forwarder)
- `make enable-dnsmasq`

### dnsdist (DoH frontend)
- `make dnsdist`
- `make dnsdist-status`

### DNS warm‑up (dns‑warm subsystem)

- `make dns-warm-install` — Install dns‑warm user, directories, scripts, and systemd units
- `make dns-warm-enable` — Enable and start the dns‑warm timer (periodic warm)
- `make dns-warm-disable` — Disable the timer
- `make dns-warm-start` — Run a single warm‑up cycle immediately (oneshot)
- `make dns-warm-stop` — Stop the oneshot service
- `make dns-warm-status` — Show timer + service status
- `make dns-warm-health` — Full health check (domain list, state file, resolver reachability)
- `make dns-warm-uninstall` — Remove dns‑warm components
- `make dns-warm-now` — Update domain list → run warm job → show last run + health summary


### DNS health tooling
- `make install-dns-health`
- `make check-dns`

## 🌐 Router DDNS

The router uses an event‑driven DynDNS script compatible with Asuswrt‑Merlin.
The DDNS pipeline is intentionally minimal: a single Make target performs both deployment of secret material and execution of the DDNS update on the router.

Targets:

- `router-ddns`
  Performs the full DDNS pipeline:

  - Generates the .ddns_confidential secret bundle (RAM‑only)
  - Deploys it to /jffs/scripts/.ddds_confidential on the router
  - Executes /jffs/scripts/ddns-start once on the router
  - Relies on provider‑level idempotence (good / nochg)
  - Removes local secret material after use

  This target is idempotent, safe to re‑run, and is the canonical entry point for DDNS operations.
  
Execution model:

No cron jobs are installed.
DDNS updates are triggered manually via Make or automatically by Asuswrt‑Merlin’s native event system.


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

The router Caddy module manages the full lifecycle of the router‑side Caddy reverse proxy, including binary installation, configuration validation, certificate integration, runtime control, and autostart convergence.

- `make router-caddy` — Full converge (DDNS precheck, certs, binary install, config validation, reload, autostart)
- `make router-caddy-install` — Install Caddy binary on router
- `make router-caddy-config` — Push and validate Caddy configuration
- `make router-caddy-enable` — Ensure Caddy autostarts on boot (idempotent)
- `make router-caddy-upgrade` — Fetch latest Caddy binary, validate, restart
- `make router-caddy-check` — Full health probe (binary, version, process, config, reload)
- `make router-caddy-status` — Show Caddy process status
- `make router-caddy-health` — Check if Caddy is running
- `make router-caddy-version` — Show Caddy version
- `make router-caddy-start` — Start Caddy
- `make router-caddy-stop` — Stop Caddy
- `make router-caddy-restart` — Restart Caddy


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

## 💻 Code‑server

The local VS Code server is managed declaratively.

- `make code-server-update` — Fetchs the latest version

- `make code-server-install` — Installs or upgrades code‑server using the upstream installer.
  Always installs the latest stable release (e.g. v4.115.0).
  Idempotent: safe to re‑run. When done, run `sudo systemctl enable --now code-server@$USER`

- `make code-server-enable` — Enables the systemd user service and ensures it starts on boot.

- `make code-server-ensure-running` — Ensures code‑server is running with the correct configuration and systemd override.
  Restarts automatically if configuration changed.



### Notes

- The systemd override forces code‑server to run with the managed config at
  `~/.config/code-server/config.yaml`.
- The install target tracks upstream automatically.
- If deterministic version pinning is required, replace the installer script with a pinned release artifact.


## 🔐 WireGuard — minimal lifecycle (new architecture)

This section describes the updated WireGuard control plane, including router kernel‑module autoload and runtime preflight.

Full architecture diagram:
  → docs/architecture.md

Key invariants:

- NAS is the authoritative control plane (TSVs, keys, generation, deployment)
- Router is a runtime-only node (wg + ip, no wg-quick, no router-side scripts)
- Router kernel module is guaranteed via:
  - router-ensure-wg-module (boot-time autoload)
  - wg-router-preflight (runtime modprobe)
- All interfaces marked enabled in wg-interfaces.tsv are generated
- Only wgs1 (router) and wg7 (NAS) are deployed by default
- No policy engine, no transport engine, no plan compiler
- All state is intent-driven from TSV input

### 🔧 WireGuard — generation

- `make wg-generate` — Generate all WireGuard configs from authoritative TSV input.
  Produces:

  - output/router/wgs1.conf
  - output/server/wg*.conf
  - output/clients/*.conf (optional)

### 📦 WireGuard — deployment

#### Router

- `make wg-install-router` — Installs the router WireGuard config and ensures the router is module-ready.
  Includes:

  - router-ensure-wg-module — append `modprobe wireguard` to `/jffs/scripts/services-start` (idempotent)
  - wg-router-preflight — load module immediately (`modprobe wireguard`)
  - Deploy `output/router/wgs1.conf` → `/jffs/etc/wireguard/wgs1.conf`

#### NAS

- `make wg-install-nas` — Installs NAS WireGuard configs using install_file_if_changed_v2.sh.
  Copies:

  - output/server/wg7.conf → /etc/wireguard/wg7.conf
  - Installs NAS firewall script (firewall-nas.sh)

### 🚀 WireGuard — bring-up

#### Router

- `make wg-up-router` — Ensures module is loaded (wg-router-preflight), then:

  - Creates interface wgs1
  - Loads config via `wg`
  - Assigns IPs
  - Sets link up

#### NAS

- `make wg-up-nas` — Waits for router to be fully up, then:

  - Brings up wg7 via wg-quick
  - Applies generated firewall script

### 🎯 WireGuard — full converge

- `make wg-up` — Full WireGuard converge:

  - wg-generate
  - wg-install-router (with module autoload + preflight)
  - wg-install-nas
  - wg-up-router
  - wg-up-nas

This is the canonical entrypoint.

### 🛑 WireGuard — teardown

- `make wg-down-nas` — NAS disconnects first (graceful exit)

- `make wg-down-router` — Router waits for NAS to disconnect, then tears down wgs1

- `make wg-down` — Full teardown sequence

### 🧭 Notes

- Router module loading is now fully autonomous:
  - Boot-time: router-ensure-wg-module
  - Runtime: wg-router-preflight
- No router-side scripts are used except `/jffs/scripts/services-start`
- No iptables WG chains are created
- All deployment is atomic via install_file_if_changed_v2.sh
- All state is intent-driven from TSV input

## 📝 Notes

- Router targets are split into deploy vs execute where side effects exist.
  Aggregate targets compose these explicitly.
- All state is intent-driven; validation failures never modify deployed state.
- Scripts are never executed from the repository.
- Destructive targets are explicit and never run implicitly.
- Runtime reconciliation is gated; use `FORCE=1` only after reviewing drift.
- `make router-verify` asserts non‑negotiable router security invariants
  and must pass after firmware updates or reboots.
