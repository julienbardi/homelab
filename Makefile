# ============================================================
# Homelab Makefile
# ------------------------------------------------------------
# Orchestration: Gen0 → Gen1 → Gen2
# Includes lint target for safety
# ============================================================

SHELL := /bin/bash

# --- Git repo URL for homelab ---
HOMELAB_REPO := https://github.com/Jambo15/homelab.git
HOMELAB_DIR  := ~/src/homelab

.PHONY: gitcheck update
gitcheck:
	@if [ ! -d $(HOMELAB_DIR)/.git ]; then \
		echo "[Makefile] Cloning homelab repo..."; \
		mkdir -p ~/src; \
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
.PHONY: lint test clean

test:
	@echo "[Makefile] No tests defined yet"

# --- Dependencies ---
# checkmake requires pandoc for building and running its checks
deps: install-go install-pandoc install-checkmake

install-go:
	@if ! command -v go >/dev/null 2>&1; then \
		echo "[Makefile] Installing Go runtime..."; \
		apt-get update && apt-get install -y --no-install-recommends golang-go; \
	else \
		echo "[Makefile] Go runtime already installed"; \
		go version; \
	fi

remove-go:
	@echo "[Makefile] Removing Go runtime..."
	@sudo apt-get remove -y golang-go || echo "[Makefile] Go runtime not installed"
	@$(MAKE) autoremove

install-pandoc:
	@if ! command -v pandoc >/dev/null 2>&1; then \
		echo "[Makefile] Installing pandoc..."; \
		apt-get update && apt-get install -y --no-install-recommends pandoc; \
	else \
		echo "[Makefile] pandoc already installed"; \
		pandoc --version | head -n1; \
	fi

remove-pandoc:
	@echo "[Makefile] Removing pandoc..."
	@sudo apt-get remove -y pandoc || echo "[Makefile] pandoc not installed"
	@$(MAKE) autoremove

install-checkmake: install-pandoc install-go
	@echo "[Makefile] Installing checkmake (v0.2.2) using upstream Makefile..."
	@mkdir -p ~/src
	@rm -rf ~/src/checkmake
	@git clone https://github.com/mrtazz/checkmake.git ~/src/checkmake
	@cd ~/src/checkmake && git config advice.detachedHead false && git checkout 0.2.2
	@cd ~/src/checkmake && \
		BUILDER_NAME="$$(git config --get user.name || echo $$USER)" \
		BUILDER_EMAIL="$$(git config --get user.email || echo $$USER@example.com)" \
		make
	@sudo install -m 0755 ~/src/checkmake/cmd/checkmake/checkmake /usr/local/bin/checkmake
	@checkmake --version


remove-checkmake:
	@echo "[Makefile] Removing checkmake..."
	@sudo rm -f /usr/local/bin/checkmake
	@rm -rf ~/src/checkmake
	@$(MAKE) autoremove

headscale-build: install-go
	@echo "[Makefile] Building Headscale..."
	@if ! command -v headscale >/dev/null 2>&1; then \
		go install github.com/juanfont/headscale/cmd/headscale@v0.27.1; \
	else \
		headscale version; \
	fi

# --- Default target ---
all: gitcheck gen0 gen1 gen2

# --- Gen0: foundational services ---
gen0: headscale coredns dns firewall audit

CONFIG_FILES = config/headscale.yaml config/derp.yaml

headscale: $(CONFIG_FILES)
	@echo "[Makefile] Running setup_headscale.sh..."
	@bash gen0/setup_headscale.sh

coredns:
	@echo "[Makefile] Running setup_coredns.sh..."
	@bash gen0/setup_coredns.sh

dns:
	@echo "[Makefile] Running dns_setup.sh..."
	@bash gen0/dns_setup.sh

firewall:
	@echo "[Makefile] Running wg_firewall_apply.sh..."
	@bash gen0/wg_firewall_apply.sh

audit:
	@echo "[Makefile] Running router_audit.sh..."
	@bash gen0/router_audit.sh

# --- Gen1: helpers ---
gen1: caddy tailnet rotate wg-baseline namespaces

caddy:
	@echo "[Makefile] Running caddy-reload.sh..."
	@bash gen1/caddy-reload.sh

tailnet:
	@echo "[Makefile] Running tailnet.sh <device-name>..."
	@bash gen1/tailnet.sh test-device

rotate:
	@echo "[Makefile] Running rotate-unbound-rootkeys.sh..."
	@bash gen1/rotate-unbound-rootkeys.sh

wg-baseline:
	@echo "[Makefile] Running wg_baseline.sh <client-name>..."
	@bash gen1/wg_baseline.sh test-client

namespaces: headscale
	@echo "[Makefile] Running namespaces_headscale.sh..."
	@bash gen1/namespaces_headscale.sh

# --- Gen2: site artifact ---
gen2: site

site:
	@echo "[Makefile] Deploying site/index.html..."
	@cp gen2/site/index.html /var/www/html/index.html

# --- Lint target ---

lint: lint-scripts lint-config lint-makefile

lint-scripts:
	@bash -n gen0/*.sh gen1/*.sh scripts/*.sh
	@bash -n gen1/namespaces_headscale.sh

lint-config:
	@headscale configtest -c config/headscale.yaml || (echo "Headscale config invalid!" && exit 1)

lint-makefile:
	@if command -v checkmake >/dev/null 2>&1; then \
		echo "[Makefile] Running checkmake..."; \
		checkmake Makefile; \
		checkmake --version; \
	else \
		echo "[Makefile] checkmake not installed, using make -n fallback"; \
		make -n all >/dev/null; \
	fi

# --- Clean target ---
clean:
	@echo "[Makefile] Cleaning generated artifacts..."
	@rm -f /etc/headscale/db.sqlite
	@rm -f /etc/wireguard/*.conf.generated
	@rm -f /etc/wireguard/*.key.generated
	@rm -f /etc/wireguard/qr/*.qr

# --- Shared autoremove helper ---
autoremove:
	@echo "[Makefile] Cleaning up unused dependencies..."
	@sudo apt-get autoremove -y