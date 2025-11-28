# ============================================================
# Homelab Makefile
# ------------------------------------------------------------
# Orchestration: Gen0 → Gen1 → Gen2
# Includes lint target for safety
# ============================================================

SHELL := /bin/bash
HOMELAB_REPO := https://github.com/Jambo15/homelab.git
HOMELAB_DIR  := $(HOME)/src/homelab

BUILDER_NAME := $(shell git config --get user.name)
BUILDER_EMAIL := $(shell git config --get user.email)
export BUILDER_NAME
export BUILDER_EMAIL

# --- Includes (ordered by prefix) ---
include mk/01_common.mk      # global macros, helpers, logging (must come first)
include mk/10_groups.mk      # group membership enforcement (security bootstrap)
include mk/20_deps.mk        # package dependencies (apt installs, base tools)
include mk/30_generate.mk    # generation helpers (cert/key creation, QR codes)
include mk/40_acme.mk        # ACME client orchestration (Let's Encrypt, etc.)
include mk/50_certs.mk       # certificate handling (issue, renew, deploy)
include mk/60_unbound.mk     # Unbound DNS resolver setup
include mk/70_coredns.mk     # CoreDNS setup and deployment
include mk/80_tailnet.mk     # Tailscale/Headscale orchestration
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
.PHONY: test logs clean
.PHONY: install-unbound install-coredns install-wireguard-tools install-dnsutils clean clean-soft

# Ensure group membership before running logs
logs: journal-access
	@echo "Ensuring /var/log/homelab exists and is writable..."
	@sudo mkdir -p /var/log/homelab
	@sudo chown $(shell id -un):$(shell id -gn) /var/log/homelab

test: logs
	@echo "Running run_as_root harness..."
	@bash $(HOME)/src/homelab/scripts/test_run_as_root.sh

# --- Default target ---
# Ensure group membership is enforced before full orchestration
all:harden-groups gitcheck gen0 gen1 gen2
	@echo "[make] Completed full orchestration (harden-groups → gen0 → gen1 → gen2)"

# --- Dependencies for Gen0 services ---
install-unbound:
	@$(call apt_install,unbound,unbound)


install-coredns:
	@$(call apt_install,coredns,coredns)

install-wireguard-tools:
	@$(call apt_install,wg,wireguard-tools)

install-dnsutils:
	@$(call apt_install,dig,dnsutils)

# --- Gen0: foundational services ---
# Ensure group membership is enforced before starting foundational services
gen0: harden-groups setup-subnet-router headscale dns coredns
	@echo "[make] Running gen0 foundational services..."

# --- Subnet router deployment ---
# Source: $(HOMELAB_DIR)/scripts/setup/setup-subnet-router.sh (tracked in Git)
# Target: /usr/local/bin/setup-subnet-router (systemd service uses this)
# To update: edit in repo, commit, then run `make setup-subnet-router`
SCRIPT_SRC  := $(HOMELAB_DIR)/scripts/setup/setup-subnet-router.sh
SCRIPT_DST  := /usr/local/bin/setup-subnet-router

# Order-only prerequisite: require file to exist, but don't try to build it
setup-subnet-router: update install-wireguard-tools | $(SCRIPT_SRC)
	@echo "[make] Deploying subnet router script from Git..."
	@if [ ! -f "$(SCRIPT_SRC)" ]; then \
		echo "[make] ERROR: $(SCRIPT_SRC) not found"; exit 1; \
	fi
	@COMMIT_HASH=$$(git -C $(HOMELAB_DIR) rev-parse --short HEAD); \
		$(call run_as_root,cp $(SCRIPT_SRC) $(SCRIPT_DST)); \
		$(call run_as_root,chown root:root $(SCRIPT_DST)); \
		$(call run_as_root,chmod 0755 $(SCRIPT_DST)); \
		$(call run_as_root,systemctl restart subnet-router.service); \
		echo "[make] Deployed commit $$COMMIT_HASH to $(SCRIPT_DST) and restarted subnet-router.service"

# Top-level Makefile (snippet)
# ensure prerequisites/config files are present before running the setup script
headscale: install-go config/headscale.yaml config/derp.yaml deploy-headscale
	@echo "Running Headscale setup script..."
	@bash scripts/setup/setup_headscale.sh

.PHONY: coredns

/etc/coredns/Corefile:
	run_as_root chmod 0755 /etc/coredns; \
	sudo install -o coredns -g coredns -m 640 /home/julie/src/homelab/config/coredns/Corefile /etc/coredns/Corefile;
	
coredns: dns headscale install-coredns deploy-coredns /etc/coredns/Corefile
	@echo "[make] coredns";
	@export SCRIPT_NAME="coredns"; . scripts/lib/run_as_root.sh && \
	if ! getent passwd coredns >/dev/null; then \
		sudo useradd --system --no-create-home --shell /usr/sbin/nologin coredns; \
	fi; \
	run_as_root mkdir -p /etc/coredns /var/lib/coredns; \
	run_as_root chown -R coredns:coredns /etc/coredns /var/lib/coredns || true; \
	run_as_root bash scripts/setup/setup_coredns.sh;

dns: install-unbound install-dnsutils
	@$(call run_as_root,bash scripts/setup/dns_setup.sh)

# --- Gen1: helpers ---
gen1: caddy deploy-headscale-yaml rotate wg-baseline namespaces audit
	@echo "[make] Running gen1 helper scripts..."

audit: headscale coredns dns setup-subnet-router
	@$(call	 run_as_root,bash scripts/audit/router_audit.sh)

.PHONY: deploy-caddyfile
deploy-caddyfile:
	@echo "[make] Deploying Caddyfile from Git → /etc/caddy"
	@sudo cp $(HOMELAB_DIR)/config/caddy/Caddyfile /etc/caddy/Caddyfile
	@sudo chown root:root /etc/caddy/Caddyfile
	@sudo chmod 644 /etc/caddy/Caddyfile
	@echo "[make] ✅ Caddyfile deployed successfully"

caddy: deploy-caddy deploy-caddyfile
	@echo "[make] Restarting caddy service (Restart flushes out stale matcher references and old routes)"
	@$(call run_as_root,systemctl restart caddy)

caddy-reload: deploy-caddy deploy-caddyfile
	@echo "[make] Reloading caddy service (hot reload, fragile, only if you are confident, use 'make caddy' with restart otherwise)"
	@$(call run_as_root,bash scripts/helpers/caddy-reload.sh)

.PHONY: deploy-headscale-yaml
HEADSCALE_SRC := /home/julie/src/homelab/config/headscale.yaml
HEADSCALE_DST := /etc/headscale/headscale.yaml
deploy-headscale-yaml: deploy-headscale
	@echo "[make] Deploying headscale.yaml..."
	@# Validate YAML before deploying
	@python3 -c "import yaml,sys; yaml.safe_load(open('$(HEADSCALE_SRC)')); print('YAML OK')"
	@# Atomic copy with correct permissions
	@sudo install -o headscale -g headscale -m 640 $(HEADSCALE_SRC) $(HEADSCALE_DST)
	@echo "File copied to $(HEADSCALE_DST)"
	@# Restart service only if running
	@sudo systemctl restart headscale
	@echo "[make] Headscale service restarted"

rotate:
	@$(call	 run_as_root,bash scripts/helpers/rotate-unbound-rootkeys.sh)

wg-baseline:
	@$(call	 run_as_root,bash scripts/helpers/wg_baseline.sh test-client)

namespaces: headscale
	@$(call	 run_as_root,bash scripts/helpers/namespaces_headscale.sh)

# --- Gen2: site artifact ---
gen2: site
	@echo "[make] Running gen2 site deployment..."

# By default site.sh reloads: caddy nginx apache2 lighttpd traefik
# You can override at runtime, e.g.:
#   make site SERVICES="caddy"
#   make site SERVICES="caddy nginx"
site: caddy audit
	@$(call run_as_root,SERVICES="$(SERVICES)" bash scripts/deploy/site.sh)

# --- Clean target ---
WIREGUARD_DIR := /etc/wireguard

clean-soft:
	@$(call run_as_root,rm -f \
		$(WIREGUARD_DIR)/*.conf.generated \
		$(WIREGUARD_DIR)/*.key.generated \
		$(WIREGUARD_DIR)/qr/*.qr)

clean: clean-soft
	$(call run_as_root,systemctl stop headscale || true)
	@$(call run_as_root,rm -f /etc/headscale/db.sqlite)

