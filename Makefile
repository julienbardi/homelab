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
HOMELAB_REPO := https://github.com/Jambo15/homelab.git
HOMELAB_DIR  := $(HOME)/src/homelab

BUILDER_NAME := $(shell git config --get user.name)
BUILDER_EMAIL := $(shell git config --get user.email)
export BUILDER_NAME
export BUILDER_EMAIL

HEADSCALE_CONFIG := /etc/headscale/config.yaml
export HEADSCALE_CONFIG

# --- Includes (ordered by prefix) ---
include mk/10_groups.mk      # group membership enforcement (security bootstrap)
include mk/20_deps.mk        # package dependencies (apt installs, base tools)
include mk/30_generate.mk    # generation helpers (cert/key creation, QR codes)
include mk/40_acme.mk        # ACME client orchestration (Let's Encrypt, etc.)
include mk/50_certs.mk       # certificate handling (issue, renew, deploy)
include mk/60_unbound.mk     # Unbound DNS resolver setup
include mk/70_coredns.mk     # CoreDNS setup and deployment
include mk/80_tailnet.mk     # Tailscale/Headscale orchestration
include mk/81_headscale.mk   # Headscale-specific targets (Noise key rotation, etc.)
include mk/82_tailscaled.mk  # tailscaled client management (ACLs, ephemeral keys, systemd units, status/logs)
include mk/90_dns-health.mk  # DNS health checks and monitoring
include mk/99_lint.mk        # lint and safety checks (always last)

# ============================================================
# Makefile — homelab certificate orchestration
# ============================================================

# Default target
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  make issue              # Issue new RSA+ECC certs"
	@echo "  make renew              # Renew ECC (RSA fallback)"
	@echo "  make prepare            # Prepare canonical store"
	@echo "  make deploy-caddy       # Deploy certs to Caddy"
	@echo "  make deploy-coredns     # Deploy certs to CoreDNS"
	@echo "  make deploy-headscale   # Deploy certs to Headscale (optional)"
	@echo "  make deploy-router      # Deploy certs to Asus router"
	@echo "  make deploy-diskstation # Deploy certs to Synology DSM"
	@echo "  make deploy-qnap        # Deploy certs to QNAP"
	@echo "  make all-caddy          # Renew+prepare+deploy+validate Caddy"
	@echo "  make all-router         # Renew+prepare+deploy+validate Router"
	@echo "  make all-diskstation    # Renew+prepare+deploy+validate DiskStation"
	@echo "  make all-qnap           # Renew+prepare+deploy+validate QNAP"
	@echo ""
	@echo "Provisioning targets (systemd watchers):"
	@echo "  make setup-cert-watch-caddy     Install + enable path unit for Caddy reload"
	@echo "  make setup-cert-watch-headscale Install + enable path unit for Headscale reload"
	@echo "  make setup-cert-watch-coredns   Install + enable path unit for CoreDNS reload"
	@echo ""
	@echo "Bootstrap targets (one-shot setup + lifecycle):"
	@echo "  make bootstrap-caddy       Run setup-cert-watch-caddy + all-caddy"
	@echo "  make bootstrap-headscale   Run setup-cert-watch-headscale + all-headscale"
	@echo "  make bootstrap-coredns     Run setup-cert-watch-coredns + all-coredns"

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
	@$(run_as_root) systemctl disable tailscaled-family.service tailscaled-guest.service tailscaled || true
	@$(run_as_root) rm -f /etc/systemd/system/tailscaled-family.service /etc/systemd/system/tailscaled-guest.service || true
	@$(run_as_root) systemctl daemon-reload
	@echo "[make] ✅ Cleaned tailscaled units and disabled services"

.PHONY: reload
reload:
	@$(run_as_root) systemctl daemon-reload
	@echo "[make] 🔄 systemd reloaded"

.PHONY: restart
restart:
	@$(run_as_root) systemctl restart tailscaled tailscaled-family.service tailscaled-guest.service
	@echo "[make] 🔁 Restarted tailscaled + family + guest services"

test: logs
	@echo "Running run_as_root harness..."
	@$(run_as_root) bash $(HOMELAB_DIR)/scripts/test_run_as_root.sh

.PHONY: caddy deploy-caddy
caddy: gitcheck
	@echo "[make] Deploying Caddyfile and reloading Caddy"
	@$(run_as_root) bash $(HOMELAB_DIR)/scripts/helpers/caddy-reload.sh

# --- Default target ---
all: harden-groups gitcheck gen0 gen1 gen2
	@echo "[make] Completed full orchestration (harden-groups → gen0 → gen1 → gen2)"

# --- Gen0: foundational services ---
gen0: harden-groups setup-subnet-router headscale tailscaled dns coredns
	@echo "[make] Running gen0 foundational services..."

# --- Subnet router deployment ---
SCRIPT_SRC  := $(HOMELAB_DIR)/scripts/setup/setup-subnet-router.sh
SCRIPT_DST  := /usr/local/bin/setup-subnet-router

setup-subnet-router: update install-wireguard-tools | $(SCRIPT_SRC)
	@echo "[make] Deploying subnet router script from Git..."
	@if [ ! -f "$(SCRIPT_SRC)" ]; then \
		echo "[make] ERROR: $(SCRIPT_SRC) not found"; exit 1; \
	fi
	@COMMIT_HASH=$$(git -C $(HOMELAB_DIR) rev-parse --short HEAD); \
		$(run_as_root) cp $(SCRIPT_SRC) $(SCRIPT_DST); \
		$(run_as_root) chown root:root $(SCRIPT_DST); \
		$(run_as_root) chmod 0755 $(SCRIPT_DST); \
		$(run_as_root) systemctl restart subnet-router.service; \
		echo "[make] Deployed commit $$COMMIT_HASH to $(SCRIPT_DST) and restarted subnet-router.service"

# --- Headscale orchestration ---
headscale: harden-groups install-go config/headscale.yaml config/derp.yaml deploy-headscale
	@echo "Running Headscale setup script..."
	@$(run_as_root) bash scripts/setup/setup_headscale.sh

.PHONY: tailscaled
tailscaled: headscale tailscaled-family tailscaled-guest enable-tailscaled start-tailscaled tailscaled-status
	@COMMIT_HASH=$$(git -C $(HOMELAB_DIR) rev-parse --short HEAD); \
		echo "[make] Completed tailscaled orchestration at commit $$COMMIT_HASH"

.PHONY: coredns

/etc/coredns/Corefile:
	@$(run_as_root) chmod 0755 /etc/coredns; \
	$(run_as_root) install -o coredns -g coredns -m 640 $(HOMELAB_DIR)/config/coredns/Corefile /etc/coredns/Corefile

coredns: dns headscale deploy-coredns /etc/coredns/Corefile
	@echo "[make] coredns"
	@$(run_as_root) env SCRIPT_NAME=coredns bash $(HOMELAB_DIR)/scripts/setup/deploy_certificates.sh renew FORCE=$(FORCE) || { echo "[make] ❌ renew failed"; exit 1; }

	#@$(run_as_root) bash -c 'export SCRIPT_NAME="coredns"; $(HOMELAB_DIR)/scripts/lib/run_as_root.sh && run_as_root'

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

enable-systemd: install-systemd ## Enable and start the watcher and ensure Unbound drop-in is active
	@echo "[make] Enabling and starting path watcher and ensuring unbound drop-in is active..."
	@$(run_as_root) systemctl enable --now unbound-ctl-fix.path || true
	@$(run_as_root) systemctl reset-failed unbound-ctl-fix.service unbound-ctl-fix.path || true
	@$(run_as_root) systemctl start unbound-ctl-fix.service || true
	# restart unbound so ExecStartPost runs and sets socket ownership in same context
	@$(run_as_root) systemctl restart unbound || true
	@$(run_as_root) systemctl status unbound --no-pager || true

verify-systemd: ## Show status and socket ownership
	@echo "[make] Status and socket ownership:"
	@$(run_as_root) systemctl status unbound --no-pager || true
	@$(run_as_root) systemctl status unbound-ctl-fix.path unbound-ctl-fix.service --no-pager || true
	@$(run_as_root) ls -l /run/unbound.ctl /var/run/unbound.ctl || true
	@$(run_as_root) -u unbound sh -c 'unbound-control status' || true

uninstall-systemd: ## Remove units and reload systemd
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
