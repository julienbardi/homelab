# ============================================================
# Homelab Makefile
# ------------------------------------------------------------
# Orchestration: Gen0 → Gen1 → Gen2
# Includes lint target for safety
# ============================================================

SHELL := /bin/bash

# --- Git repo URL for homelab ---
HOMELAB_REPO := https://github.com/Jambo15/homelab.git
# Normalize to absolute paths derived from HOME (no ~, no accidental spaces)
HOMELAB_DIR  := $(HOME)/src/homelab

BUILDER_NAME := $(shell git config --get user.name)
BUILDER_EMAIL := $(shell git config --get user.email)
export BUILDER_NAME
export BUILDER_EMAIL

# --- Privilege guard with id -u (0 if root) evaluated at runtime not at parse time ---
run_as_root = @bash -c 'if [ "$$(id -u)" -eq 0 ]; then $(1); else sudo bash -c "$(1)"; fi'

.PHONY: gitcheck update
gitcheck:
	@if [ ! -d $(HOMELAB_DIR)/.git ]; then \
		echo "[Makefile] Cloning homelab repo..."; \
		mkdir -p $(HOME)/src; \
		git clone $(HOMELAB_REPO) $(HOMELAB_DIR); \
	else \
		echo "[Makefile] homelab repo already present at $(HOMELAB_DIR)"; \
		git -C $(HOMELAB_DIR) rev-parse --short HEAD; \
	fi

update: gitcheck
	@echo "[Makefile] Updating homelab repo..."
	@git -C $(HOMELAB_DIR) pull --rebase
	@echo "[Makefile] Repo now at commit $$(git -C $(HOMELAB_DIR) rev-parse --short HEAD)"

.PHONY: all gen0 gen1 gen2 deps install-go remove-go install-checkmake remove-checkmake headscale-build
.PHONY: setup-subnet-router
.PHONY: lint test clean
.PHONY: install-unbound install-coredns install-wireguard-tools install-dnsutils \
		remove-go remove-pandoc remove-checkmake clean clean-soft autoremove

test:
	@echo "[Makefile] No tests defined yet"

# --- Dependencies ---
deps: install-go install-pandoc install-checkmake

install-go:
	$(call apt_install,go,golang-go)

remove-go:
	$(call apt_remove,golang-go)

install-pandoc:
	$(call apt_install,pandoc,pandoc)

remove-pandoc:
	$(call apt_remove,pandoc)

install-checkmake: install-pandoc install-go
	@echo "[Makefile] Installing checkmake (v0.2.2) using upstream Makefile..."
	@mkdir -p $(HOME)/src
	@rm -rf $(HOME)/src/checkmake
	@git clone https://github.com/mrtazz/checkmake.git $(HOME)/src/checkmake
	@cd $(HOME)/src/checkmake && git config advice.detachedHead false && git checkout 0.2.2
	@cd $(HOME)/src/checkmake && \
		BUILDER_NAME="$$(git config --get user.name)" \
		BUILDER_EMAIL="$$(git config --get user.email)" \
		make
	$(call run_as_root,install -m 0755 $(HOME)/src/checkmake/checkmake /usr/local/bin/checkmake)
	@echo "[Makefile] Installed checkmake built by $$(git config --get user.name) <$$(git config --get user.email)>"
	@checkmake --version

remove-checkmake:
	$(call remove_cmd,checkmake,rm -f /usr/local/bin/checkmake && rm -rf $(HOME)/src/checkmake)

headscale-build: install-go
	@echo "[Makefile] Building Headscale..."
	@if ! command -v headscale >/dev/null 2>&1; then \
		go install github.com/juanfont/headscale/cmd/headscale@v0.27.1; \
	else \
		headscale version; \
	fi

# --- Default target ---
all: gitcheck gen0 gen1 gen2
	@echo "[Makefile] Completed full orchestration (gen0 → gen1 → gen2)"

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
gen0: setup-subnet-router headscale dns coredns firewall
	@echo "[Makefile] Running gen0 foundational services..."

# --- Subnet router deployment ---
# Source: $(HOMELAB_DIR)/scripts/setup/setup-subnet-router.sh (tracked in Git)
# Target: /usr/local/bin/setup-subnet-router (systemd service uses this)
# To update: edit in repo, commit, then run `make setup-subnet-router`
SCRIPT_SRC  := $(HOMELAB_DIR)/scripts/setup/setup-subnet-router.sh
SCRIPT_DST  := /usr/local/bin/setup-subnet-router

# Order-only prerequisite: require file to exist, but don't try to build it
setup-subnet-router: update | $(SCRIPT_SRC)
	@echo "[Makefile] Deploying subnet router script from Git..."
	@if [ ! -f "$(SCRIPT_SRC)" ]; then \
		echo "[Makefile] ERROR: $(SCRIPT_SRC) not found"; exit 1; \
	fi
	COMMIT_HASH=$$(git -C "$(HOMELAB_DIR)" rev-parse --short HEAD); \
	$(call run_as_root,cp "$(SCRIPT_SRC)" "$(SCRIPT_DST)")
	$(call run_as_root,chown root:root "$(SCRIPT_DST)")
	$(call run_as_root,chmod 0755 "$(SCRIPT_DST)")
	$(call run_as_root,systemctl restart subnet-router.service)
	@echo "[Makefile] Deployed commit $$COMMIT_HASH to $(SCRIPT_DST) and restarted subnet-router.service"
	
CONFIG_FILES = config/headscale.yaml config/derp.yaml

headscale: install-go $(CONFIG_FILES)
	@$(call	 run_as_root,bash scripts/setup/setup_headscale.sh)

coredns: dns install-coredns
	@$(call	 run_as_root,bash scripts/setup/setup_coredns.sh)

dns: install-unbound install-dnsutils
	@$(call run_as_root,bash scripts/setup/dns_setup.sh)

firewall: install-wireguard-tools
	@$(call	 run_as_root,bash scripts/setup/wg_firewall_apply.sh)

# --- Gen1: helpers ---
gen1: caddy tailnet rotate wg-baseline namespaces audit
	@echo "[Makefile] Running gen1 helper scripts..."

audit: headscale coredns dns firewall
	@$(call	 run_as_root,bash scripts/audit/router_audit.sh)

caddy:
	@$(call	 run_as_root,bash scripts/helpers/caddy-reload.sh)

tailnet:
	@$(call	 run_as_root,bash scripts/helpers/tailnet.sh test-device)

rotate:
	@$(call	 run_as_root,bash scripts/helpers/rotate-unbound-rootkeys.sh)

wg-baseline:
	@$(call	 run_as_root,bash scripts/helpers/wg_baseline.sh test-client)

namespaces: headscale
	@$(call	 run_as_root,bash scripts/helpers/namespaces_headscale.sh)

# --- Gen2: site artifact ---
gen2: site
	@echo "[Makefile] Running gen2 site deployment..."

# By default site.sh reloads: caddy nginx apache2 lighttpd traefik
# You can override at runtime, e.g.:
#   make site SERVICES="caddy"
#   make site SERVICES="caddy nginx"
site: caddy audit
	@$(call run_as_root,SERVICES="$(SERVICES)" bash scripts/deploy/site.sh)

# --- Lint target ---
lint: lint-scripts lint-config lint-makefile

lint-scripts:
	 @bash -n scripts/setup/*.sh scripts/helpers/*.sh scripts/audit/*.sh scripts/deploy/*.sh

lint-config:
	@$(call run_as_root,headscale configtest -c config/headscale.yaml) || \
		(echo "Headscale config invalid!" && exit 1)

lint-makefile:
	@if command -v checkmake >/dev/null 2>&1; then \
		$(call run_as_root,checkmake Makefile); \
		$(call run_as_root,checkmake --version); \
	else \
		make -n all >/dev/null; \
	fi

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

# --- Shared helpers ---
autoremove:
	@echo "[Makefile] Cleaning up unused dependencies..."
	@$(call run_as_root,apt-get autoremove -y)

define apt_install
	@if ! command -v $(1) >/dev/null 2>&1; then \
		$(call run_as_root,apt-get update && apt-get install -y --no-install-recommends $(2)); \
	else \
		if [ "$(1)" = "go" ]; then $(1) version; \
		elif [ "$(1)" = "dig" ]; then $(1) -v; \
		else $(1) --version | head -n1; fi; \
	fi
endef

define apt_remove
	@$(call remove_cmd,$(1),apt-get remove -y $(1) || echo "[Makefile] $(1) not installed")
endef

define remove_cmd
	@echo "[Makefile] Removing $(1)..."
	@$(call run_as_root,$(2))
	@$(MAKE) autoremove
endef