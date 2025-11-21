# ============================================================
# Homelab Makefile
# ------------------------------------------------------------
# Orchestration: Gen0 → Gen1 → Gen2
# Includes lint target for safety
# ============================================================

SHELL := /bin/bash

.PHONY: all gen0 gen1 gen2 lint clean namespaces deps test lint-makefile

test:
	@echo "[Makefile] No tests defined yet"

# --- Dependencies ---
deps: deps-checkmake

deps-checkmake:
	@if command -v checkmake >/dev/null 2>&1; then \
		echo "[Makefile] checkmake already installed"; \
	else \
		echo "[Makefile] checkmake not installed, please build manually"; \
	fi

# --- Default target ---
all: gen0 gen1 gen2

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
	@bash -n gen0/*.sh gen1/*.sh scripts/*.sh scripts/gen1/*.sh
	@bash -n gen1/namespaces_headscale.sh

lint-config:
	@headscale configtest -c config/headscale.yaml || (echo "Headscale config invalid!" && exit 1)

lint-makefile: lint-makefile-check lint-makefile-fallback

lint-makefile-check:
	@if command -v checkmake >/dev/null 2>&1; then \
		checkmake Makefile; \
	fi

lint-makefile-fallback:
	@if ! command -v checkmake >/dev/null 2>&1; then \
		echo "[Makefile] checkmake not installed, using make -n fallback"; \
		make -n all >/dev/null; \
	fi

# --- Clean target ---
clean:
	@echo "[Makefile] Cleaning generated artifacts..."
	@rm -f /etc/headscale/db.sqlite
	@rm -f /etc/wireguard/*.conf
	@rm -f /etc/wireguard/*.key
	@rm -f /etc/wireguard/qr/*.qr

