# --------------------------------------------------------------------
# Makefile (root)
# --------------------------------------------------------------------
# CONTRACT:
# - Includes mk/01_common.mk to set run_as_root.
# - Recipes call $(run_as_root) with argv tokens.
# - Escape operators (\>, \|, \&\&, \|\|).
# --------------------------------------------------------------------

include mk/01_common.mk

SHELL := /bin/bash
HOMELAB_REPO := git@github.com:Jambo15/homelab.git
HOMELAB_DIR  := .# $(HOME)/src/homelab

BUILDER_NAME := $(shell git config --get user.name)
BUILDER_EMAIL := $(shell git config --get user.email)
export BUILDER_NAME
export BUILDER_EMAIL

HEADSCALE_CONFIG := /etc/headscale/config.yaml
export HEADSCALE_CONFIG

# --- Includes (ordered by prefix) ---
include mk/00_prereqs.mk
include mk/10_groups.mk      # group membership enforcement (security bootstrap)
include mk/20_deps.mk        # package dependencies (apt installs, base tools)
include mk/30_generate.mk    # generation helpers (cert/key creation, QR codes)
include mk/31_setup-subnet-router.mk # Subnet router orchestration
include mk/40_acme.mk        # ACME client orchestration (Let's Encrypt, etc.)
include mk/40_code-server.mk
include mk/40_wireguard.mk   # Wireguard orchestration
include mk/40_caddy.mk
include mk/50_certs.mk       # certificate handling (issue, renew, deploy)
include mk/50_dnsmasq.mk
include mk/60_unbound.mk     # Unbound DNS resolver setup
include mk/70_dnsdist.mk     #
include mk/71_dns-warm.mk    # DNS cache warming (systemd timer)
include mk/70_dnscrypt-proxy.mk   # dnscrypt-proxy setup and deployment
include mk/80_tailnet.mk     # Tailscale/Headscale orchestration
include mk/81_headscale.mk   # Headscale-specific targets (Noise key rotation, etc.)
include mk/82_tailscaled.mk  # tailscaled client management (ACLs, ephemeral keys, systemd units, status/logs)
include mk/90_dns-health.mk  # DNS health checks and monitoring
include mk/90_converge.mk
include mk/99_lint.mk        # lint and safety checks (always last)

# ============================================================
# Makefile — homelab certificate orchestration
# ============================================================

# Default target
.PHONY: help
help:
	@echo "[make] Available targets:"
	@echo ""
	@echo "  Package and preflight"
	@echo "	   make prereqs            # Install prerequisite tools (curl, jq, git, nftables, ndppd, dns utils, admin helpers)"
	@echo "    make deps               # Install system dependencies (services, builds, Tailscale, WireGuard, dnsmasq, Unbound, etc.)"
	@echo "    make apt-update         # Force refresh apt cache (normally cached for $(APT_UPDATE_MAX_AGE)s)"
	@echo "    make check-prereqs      # Verify required host commands (sudo, apt-get, git, ip, wg, etc.)"
	@echo ""
	@echo "  Linting"
	@echo "    make lint               # Run permissive lint suite (shellcheck, checkmake, spell, headscale configtest)"
	@echo "    make lint-fast          # Fast lint (shell syntax, shellcheck, checkmake) - permissive"
	@echo "    make lint-all           # Full permissive lint (fast + spell + headscale)"
	@echo "    make lint-ci            # STRICT CI lint (fails on any ShellCheck/checkmake/codespell/aspell issues)"
	@echo ""
	@echo "  Certificate lifecycle"
	@echo "    make issue              # Issue new RSA+ECC certs"
	@echo "    make renew              # Renew ECC (RSA fallback)"
	@echo "    make prepare            # Prepare canonical store (deployable certs)"
	@echo ""
	@echo "  Deploy targets"
	@echo "    make deploy-caddy       # Deploy certs to Caddy"
	@echo "    make deploy-coredns     # Deploy certs to CoreDNS"
	@echo "    make deploy-headscale   # Deploy certs to Headscale (optional)"
	@echo "    make deploy-router      # Deploy certs to Asus router"
	@echo "    make deploy-diskstation # Deploy certs to Synology DSM"
	@echo "    make deploy-qnap        # Deploy certs to QNAP"
	@echo ""
	@echo "  Combined workflows"
	@echo "    make all-caddy          # Renew + prepare + deploy + validate Caddy"
	@echo "    make all-router         # Renew + prepare + deploy + validate Router"
	@echo "    make all-diskstation    # Renew + prepare + deploy + validate DiskStation"
	@echo "    make all-qnap           # Renew + prepare + deploy + validate QNAP"
	@echo ""
	@echo "  Watchers and bootstrap"
	@echo "    make setup-cert-watch-caddy     # Install + enable Caddy path unit for reload"
	@echo "    make setup-cert-watch-headscale # Install + enable Headscale path unit for reload"
	@echo "    make setup-cert-watch-coredns   # Install + enable CoreDNS path unit for reload"
	@echo "    make bootstrap-caddy            # setup watcher + all-caddy"
	@echo "    make bootstrap-headscale        # setup watcher + all-headscale"
	@echo "    make bootstrap-coredns          # setup watcher + all-coredns"
	@echo ""
	@echo "  Repo and preflight"
	@echo "    make ensure-known-hosts         # Ensure SSH known_hosts entries (interactive)"
	@echo "    make gitcheck                   # Ensure homelab repo present"
	@echo "    make update                     # Pull latest homelab repo"
	@echo ""
	@echo "  Orchestration and services"
	@echo "    make wireguard                  # Full WireGuard orchestration (requires router setup)"
	@echo "    make wg0 .. wg7                 # Ensure server config and keys for wg0 through wg7"
	@echo "    make wg-up-<N>                  # Bring up wgN (idempotent), e.g. make wg-up-2"
	@echo "    make wg-down-<N>                # Bring down wgN (idempotent)"
	@echo "    make wg-add-peers               # Program peers from client configs into servers"
	@echo "    make wg-clean-<N>               # Revoke all clients bound to wgN (destructive)"
	@echo "    make wg-clean-list-<N>          # Preview files that would be removed for wgN"
	@echo "    make all-wg                     # Ensure all wgN configs (wg0..wg7)"
	@echo "    make all-wg-up                  # Bring up all wg interfaces (wg-up-0 .. wg-up-7)"
	@echo "    make wg-reinstall-all           # DESTRUCTIVE: stop, wipe, recreate servers+clients (interactive)"
	@echo "    make wg-status                  # Show quick status of wg interfaces and peers"
	@echo ""
	@echo "  Client management"
	@echo "    make client-<name>              # Generate client config (name may include -wgN or use IFACE=wgN)"
	@echo "    make client-list                # List client artifacts (*.conf, *.key, *.pub)"
	@echo "    make client-clean-<name>        # Revoke a single client (backup + remove runtime peer)"
	@echo "    make client-showqr-<name>       # Show QR for client (auto-create if missing)"
	@echo "    make all-clients-generate       # Generate missing clients from embedded CLIENTS"
	@echo "    make client-dashboard           # Emoji table of users/machines vs interfaces"
	@echo ""
	@echo "  DNS"
	@echo "    make dns-all                    # Install + configure Unbound + dnscrypt-proxy"
	@echo "    make dns-warm-install           # Install DNS cache warming service + timer"
	@echo "    make dns-warm-enable            # Enable and start DNS cache warming (every minute)"
	@echo "    make dns-warm-disable           # Disable DNS cache warming"
	@echo "    make dns-warm-status            # Show dns-warm service + timer status"
	@echo "    make dns-warm-uninstall         # Remove DNS cache warming service + timer"
	@echo "    make dns-runtime                # Enable DNS runtime helpers (dnsdist + dns-warm)"
	@echo "    DISABLED: make dnscrypt-proxy   # Install + configure dnscrypt-proxy (systemd unit, curated config)"
	@echo ""
	@echo "  Monitoring and system helpers"
	@echo "    make check-dns                  # Run DNS health check"
	@echo "    make install-systemd            # Install systemd units"
	@echo "    make enable-systemd             # Enable and start systemd watchers"
	@echo "    make clean                      # Cleanup (tailscaled units, etc.)"
	@echo "    make reload                     # systemd daemon-reload"
	@echo "    make restart                    # Restart tailscaled services"
	@echo "    make test                       # Run run_as_root harness"
	@echo ""
	@echo "[make] WireGuard notes:"
	@echo "  - WireGuard files live under $(WG_DIR) and are created with root ownership and 600 perms."
	@echo "  - Client names are <user>-<machine>-wgN; you may also call client-<user>-<machine> with IFACE=wgN."
	@echo "  - Backups for client-clean are stored under $(WG_DIR)/wg-client-backup-<timestamp>-<client>."
	@echo "  - A canonical clients map is supported at $(WG_DIR)/clients.map (short-name id)."
	@echo "    Example entries: 'nas 1' ; 'julie-omen30l 2' ; 'julie-s22 3'."
	@echo "  - Run '/usr/local/bin/wg-validate-clients-map' to validate clients.map (ensures 'nas 1' present, unique names and ids)."
	@echo "  - Admin-only helpers (assign/cleanup) live in /usr/local/sbin and are intended to be invoked via $(run_as_root) or sudo."
	@echo ""
	@echo "[make] Notes:"
	@echo "  - make deps now installs developer tools used by lint: shellcheck, codespell, aspell, checkmake."
	@echo "  - The Makefile caches apt-get update for $(APT_UPDATE_MAX_AGE) seconds; use 'make apt-update' to force refresh."
	@echo "  - Use 'make lint-ci' in CI to enforce strict linting (fails on ShellCheck/checkmake/codespell/aspell issues)."
	@echo "  - Source builds (checkmake, headscale) are guarded by version/stamp checks to avoid unnecessary rebuilds."
	@echo "  - Use SKIP_KNOWN_HOSTS=1 to skip the interactive known_hosts check."
# --------------------------------------------------------------------

# Path to the interactive known_hosts installer
KNOWN_HOSTS_FILE := $(HOMELAB_DIR)/known_hosts_to_check.txt
KNOWN_HOSTS_SCRIPT := $(HOMELAB_DIR)/scripts/helpers/verify_and_install_known_hosts.sh

# Allow skipping in CI or when explicitly requested
SKIP_KNOWN_HOSTS ?= 0

.PHONY: ensure-known-hosts
ensure-known-hosts:
	@echo "[make] Ensuring known_hosts entries from $(KNOWN_HOSTS_FILE) (SKIP_KNOWN_HOSTS=$(SKIP_KNOWN_HOSTS))"
	@if [ "$(SKIP_KNOWN_HOSTS)" = "1" ]; then \
	  echo "[make] Skipping known_hosts check (SKIP_KNOWN_HOSTS=1)"; \
	else \
	  $(run_as_root) bash "$(KNOWN_HOSTS_SCRIPT)" "$(KNOWN_HOSTS_FILE)" || true; \
	fi

.PHONY: gitcheck update
gitcheck:
	@if [ ! -d $(HOMELAB_DIR)/.git ]; then \
		echo "[make] Cloning homelab repo..."; \
		mkdir -p $(HOME)/src; \
		git clone $(HOMELAB_REPO) $(HOMELAB_DIR); \
	else \
		echo "[make] homelab repo already present at $(HOMELAB_DIR)"; \
		git -C $(HOMELAB_DIR) rev-parse --short HEAD; \
	fi

update: gitcheck
	@echo "[make] Updating homelab repo..."
	@git -C $(HOMELAB_DIR) pull --rebase
	@echo "[make] Repo now at commit $$(git -C $(HOMELAB_DIR) rev-parse --short HEAD)"

.PHONY: all gen0 gen1 gen2 deps install-go remove-go install-checkmake remove-checkmake headscale-build
.PHONY: setup-subnet-router
.PHONY: test logs clean-soft

.PHONY: clean
clean:
	@echo "[make] Removing tailscaled role units..."
	@$(run_as_root) systemctl disable tailscaled-family.service tailscaled || true
	@$(run_as_root) rm -f /etc/systemd/system/tailscaled-family.service || true
	@$(run_as_root) systemctl daemon-reload
	@echo "[make] ✅ Cleaned tailscaled units and disabled services"

.PHONY: reload
reload:
	@$(run_as_root) systemctl daemon-reload
	@echo "[make] 🔄 systemd reloaded"

.PHONY: restart
restart:
	@$(run_as_root) systemctl restart tailscaled tailscaled-family.service
	@echo "[make] 🔁 Restarted tailscaled + family + guest services"



test: logs
	@echo "[make] Running run_as_root harness..."
	@$(run_as_root) bash $(HOMELAB_DIR)/scripts/test_run_as_root.sh

# --- Default target ---
all: harden-groups gitcheck gen0 gen1 gen2
	@echo "[make] Completed full orchestration (harden-groups → gen0 → gen1 → gen2)"

# --- Gen0: foundational services --- disabled: dnscrypt-proxy
gen0: sysctl harden-groups ensure-known-hosts setup-subnet-router headscale tailscaled dns-all dns 
	@echo "[make] Running gen0 foundational services..."

gen1: caddy tailnet rotate wg-baseline code-server

# --- Headscale orchestration ---
headscale: harden-groups config/headscale.yaml config/derp.yaml deploy-headscale
	@echo "[make] Running Headscale setup script..."
	@$(run_as_root) bash scripts/setup/setup_headscale.sh

.PHONY: tailscaled
tailscaled: headscale tailscaled-family enable-tailscaled start-tailscaled tailscaled-status
	@COMMIT_HASH=$$(git -C $(HOMELAB_DIR) rev-parse --short HEAD); \
		echo "[make] Completed tailscaled orchestration at commit $$COMMIT_HASH"

SYSTEMD_DIR = /etc/systemd/system
REPO_SYSTEMD = config/systemd

.PHONY: install-systemd enable-systemd uninstall-systemd verify-systemd

install-systemd: ## Install systemd units and reload systemd (idempotent)
	@echo "[make] Installing systemd units..."
	@if [ ! -d "$(HOMELAB_DIR)/$(REPO_SYSTEMD)" ]; then \
		echo "[make] ERROR: $(HOMELAB_DIR)/$(REPO_SYSTEMD) not found"; exit 1; \
	fi
	# ensure target dirs
	@$(run_as_root) mkdir -p $(SYSTEMD_DIR)
	@$(run_as_root) mkdir -p $(SYSTEMD_DIR)/unbound-ctl-fix.service.d
	@$(run_as_root) mkdir -p /etc/systemd/system/unbound.service.d
	# install unit files with safe perms (path+oneshot helper kept as fallback)
	@$(run_as_root) install -o root -g root -m 0644 $(HOMELAB_DIR)/$(REPO_SYSTEMD)/unbound-ctl-fix.service $(SYSTEMD_DIR)/unbound-ctl-fix.service
	@$(run_as_root) install -o root -g root -m 0644 $(HOMELAB_DIR)/$(REPO_SYSTEMD)/unbound-ctl-fix.path $(SYSTEMD_DIR)/unbound-ctl-fix.path
	@$(run_as_root) install -o root -g root -m 0644 $(HOMELAB_DIR)/$(REPO_SYSTEMD)/limit.conf $(SYSTEMD_DIR)/unbound-ctl-fix.service.d/limit.conf
	@$(run_as_root) install -o root -g root -m 0644 $(HOMELAB_DIR)/$(REPO_SYSTEMD)/unbound.service.d/99-fix-unbound-ctl.conf $(SYSTEMD_DIR)/unbound.service.d/99-fix-unbound-ctl.conf
	@$(run_as_root) systemctl daemon-reload

enable-systemd: install-systemd
	@echo "[make] Enabling and starting path watcher and ensuring unbound drop-in is active..."
	@$(run_as_root) systemctl enable --now unbound-ctl-fix.path || true
	@$(run_as_root) systemctl reset-failed unbound-ctl-fix.service unbound-ctl-fix.path || true
	@$(run_as_root) systemctl start unbound-ctl-fix.service || true
	# restart unbound so ExecStartPost runs and sets socket ownership in same context
	@$(run_as_root) systemctl restart unbound || true
	@$(run_as_root) systemctl status unbound --no-pager || true

verify-systemd:
	@echo "[make] Status and socket ownership:"
	@$(run_as_root) systemctl status unbound --no-pager || true
	@$(run_as_root) systemctl status unbound-ctl-fix.path unbound-ctl-fix.service --no-pager || true
	@$(run_as_root) ls -l /run/unbound.ctl /var/run/unbound.ctl || true
	@$(run_as_root) -u unbound sh -c 'unbound-control status' || true

uninstall-systemd:
	@echo "[make] Removing systemd units..."
	@$(run_as_root) systemctl stop --now unbound-ctl-fix.path unbound-ctl-fix.service || true
	@$(run_as_root) systemctl disable unbound-ctl-fix.path || true
	@$(run_as_root) rm -f $(SYSTEMD_DIR)/unbound-ctl-fix.path \
			  $(SYSTEMD_DIR)/unbound-ctl-fix.service \
			  $(SYSTEMD_DIR)/unbound-ctl-fix.service.d/limit.conf \
			  $(SYSTEMD_DIR)/unbound.service.d/99-fix-unbound-ctl.conf || true
	@$(run_as_root) rmdir --ignore-fail-on-non-empty $(SYSTEMD_DIR)/unbound-ctl-fix.service.d || true
	@$(run_as_root) rmdir --ignore-fail-on-non-empty $(SYSTEMD_DIR)/unbound.service.d || true
	@$(run_as_root) systemctl daemon-reload

.PHONY: wireguard
# Convenience: ensure router then run the full wireguard orchestration
wireguard: setup-subnet-router
	@echo "[make] Running wireguard orchestration (all-start)"
	@$(run_as_root) $(MAKE) -C $(HOMELAB_DIR) all-start FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) || true
	@echo "[make] wireguard orchestration complete"
