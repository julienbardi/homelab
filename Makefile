# ============================================================
# Homelab Makefile
# ------------------------------------------------------------
# Orchestration: Gen0 → Gen1 → Gen2
# Includes lint target for safety
# ============================================================

SHELL := /bin/bash

.PHONY: all gen0 gen1 gen2 lint clean

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
lint:
	@echo "[Makefile] Linting scripts..."
	@bash -n gen0/*.sh gen1/*.sh scripts/*.sh scripts/gen1/*.sh
	@echo "[Makefile] Validating Headscale config..."
	@headscale configtest -c config/headscale.yaml || (echo "Headscale config invalid!" && exit 1)

# --- Clean target ---
clean:
	@echo "[Makefile] Cleaning generated artifacts..."
	@rm -f /etc/headscale/db.sqlite
	@rm -f /etc/wireguard/*.conf
	@rm -f /etc/wireguard/*.key
	@rm -f /etc/wireguard/qr/*.qr

