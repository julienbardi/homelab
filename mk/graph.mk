# graph.mk
# --------------------------------------------------------------------
# CONTRACT:
# - Includes mk/01_common.mk to set run_as_root.
# - Recipes call $(run_as_root) with argv tokens.
# - Escape operators (\>, \|, \&\&, \|\|).
#
# - The WireGuard graph must be evaluated exactly once per make invocation.
# --------------------------------------------------------------------

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

HOMELAB_REPO := git@github.com:julienbardi/homelab.git

BUILDER_NAME := $(shell git config --get user.name)
BUILDER_EMAIL := $(shell git config --get user.email)
export BUILDER_NAME
export BUILDER_EMAIL

HEADSCALE_CONFIG := /etc/headscale/config.yaml
export HEADSCALE_CONFIG

INTERNAL_HOSTS := \
	router.bardi.ch \
	dns.bardi.ch \
	vpn.bardi.ch \
	derp.bardi.ch \
	qnap.bardi.ch \
	nas.bardi.ch \
	dev.bardi.ch \
	apt.bardi.ch

# --- Includes (order matters, therefore prefix) ---

# Step 1 — Core constants and prerequisites
include $(REPO_ROOT)/mk/00_constants.mk
include $(REPO_ROOT)/mk/00_icons.mk
include $(REPO_ROOT)/mk/00_prereqs-rust.mk
include $(REPO_ROOT)/mk/00_prereqs.mk
include $(REPO_ROOT)/mk/01_common.mk
include $(REPO_ROOT)/mk/01_core.mk

# Step 2 — Secrets subsystem
include $(REPO_ROOT)/mk/07_secrets.mk

# Step 3 — SSH layer (router)
include $(REPO_ROOT)/mk/router/05_ssh.mk

# Step 4 — Host, Router modules
include $(REPO_ROOT)/mk/host/10_route.mk
include $(REPO_ROOT)/mk/router/10_bootstrap.mk
include $(REPO_ROOT)/mk/router/20_network_dhcp_dns.mk
include $(REPO_ROOT)/mk/router/21_network_ipv6_nvram.mk
include $(REPO_ROOT)/mk/router/40_caddy.mk
include $(REPO_ROOT)/mk/router/40_control.mk
include $(REPO_ROOT)/mk/router/40_firewall.mk
include $(REPO_ROOT)/mk/router/90_health.mk

# Step 5 — Everything else
include $(REPO_ROOT)/mk/05_bootstrap_acme.mk
include $(REPO_ROOT)/mk/10_bootstrap_security.mk
include $(REPO_ROOT)/mk/10_groups.mk
include $(REPO_ROOT)/mk/10_local-tools.mk
include $(REPO_ROOT)/mk/15_local-python-env.mk
include $(REPO_ROOT)/mk/18_ipv6-invariants.mk
include $(REPO_ROOT)/mk/20_deps.mk
include $(REPO_ROOT)/mk/20_gitignore.mk
include $(REPO_ROOT)/mk/20_local-python.mk
include $(REPO_ROOT)/mk/20_sysctl.mk
include $(REPO_ROOT)/mk/25_routing.mk
include $(REPO_ROOT)/mk/30_config_validation.mk
include $(REPO_ROOT)/mk/40_acme.mk
include $(REPO_ROOT)/mk/40_code-server.mk
include $(REPO_ROOT)/mk/40_nas-caddy.mk
include $(REPO_ROOT)/mk/40_wireguard.mk
include $(REPO_ROOT)/mk/41_firewall-nas.mk
include $(REPO_ROOT)/mk/50_certs.mk
include $(REPO_ROOT)/mk/55_router-certs.mk
include $(REPO_ROOT)/mk/60_unbound.mk
include $(REPO_ROOT)/mk/70_dnsdist.mk
include $(REPO_ROOT)/mk/71_dns-warm.mk
include $(REPO_ROOT)/mk/70_apt_proxy_auto.mk
include $(REPO_ROOT)/mk/80_openssh9_pi.mk
include $(REPO_ROOT)/mk/80_tailnet.mk
include $(REPO_ROOT)/mk/81_headscale.mk
include $(REPO_ROOT)/mk/83_headscale-users.mk
include $(REPO_ROOT)/mk/84_headscale-acls.mk
include $(REPO_ROOT)/mk/85_monitoring.mk
include $(REPO_ROOT)/mk/85_tailscaled.mk
include $(REPO_ROOT)/mk/90_dns-health.mk
include $(REPO_ROOT)/mk/90_help.mk
include $(REPO_ROOT)/mk/90_converge.mk
include $(REPO_ROOT)/mk/90_systemd.mk
include $(REPO_ROOT)/mk/95_status.mk
include $(REPO_ROOT)/mk/95_watchdog.mk
include $(REPO_ROOT)/mk/99_lint.mk

# ============================================================
# ORCHESTRATION: The Bootstrap Flow
# ============================================================
# This target converges the "Zero State" to a "Functional Identity"
# 1. security-bootstrap: Generate age.key identity
# 2. acme-bootstrap: Set up directory structures and acme.sh
# 3. ensure-known-hosts: Verify SSH trust for repo/router
# ============================================================
.PHONY: bootstrap
bootstrap: sanity security-bootstrap acme-bootstrap install-pkg-sops ensure-known-hosts check-secrets-src
	@echo "------------------------------------------------------------"
	@echo "✅ GLOBAL BOOTSTRAP COMPLETE"
	@echo "📍 Next Step: make all"
	@echo "------------------------------------------------------------"

# ============================================================
# Makefile — homelab certificate orchestration
# ============================================================

# --------------------------------------------------------------------

# Path to the interactive known_hosts installer
KNOWN_HOSTS_SCRIPT := $(INSTALL_PATH)/verify_and_install_known_hosts.sh

# Allow skipping in CI or when explicitly requested
SKIP_KNOWN_HOSTS ?= 0

.PHONY: ensure-known-hosts
ensure-known-hosts: $(KNOWN_HOSTS_SCRIPT)
	@echo "🔐 Ensuring known_hosts entries..."
	@if [ "$(SKIP_KNOWN_HOSTS)" != "1" ]; then \
		timeout 1.5 bash "$(KNOWN_HOSTS_SCRIPT)" || true; \
	fi

.PHONY: gitcheck update
gitcheck:
	$(call git_clone_or_fetch,$(REPO_ROOT),$(HOMELAB_REPO),main)
	@echo "📍 homelab repo at commit $$(git -C $(REPO_ROOT) rev-parse --short HEAD)"

update: gitcheck
	@echo "⬆️ Updating homelab repo"
	@git -C $(REPO_ROOT) pull --rebase || true
	@echo "🧬 Repo now at commit $$(git -C $(REPO_ROOT) rev-parse --short HEAD)"

.PHONY: all gen0 gen1 gen2 deps install-go remove-go install-checkmake remove-checkmake
.PHONY: test logs clean-soft

.PHONY: clean
clean:
	@$(run_as_root) sh -c '\
		echo "🧹 Removing tailscaled role units"; \
		systemctl disable tailscaled-lan.service >/dev/null 2>&1 || true; \
		rm -f /etc/systemd/system/tailscaled-lan.service || true; \
		systemctl daemon-reload >/dev/null 2>&1; \
		echo "✅ Cleaned tailscaled units and disabled services"; \
	'

.PHONY: reload
reload:
	@$(run_as_root) sh -c '\
		echo "🔄 Reloading systemd units"; \
		systemctl daemon-reload; \
		echo "✅ systemd reloaded"; \
	'

.PHONY: restart
restart:
	@$(run_as_root) sh -c '\
		echo "🔄 Restarting tailscaled services"; \
		systemctl restart tailscaled >/dev/null 2>&1 || true; \
		systemctl restart tailscaled-lan.service >/dev/null 2>&1 || true; \
		echo "✅ tailscaled services restarted"; \
	'

test: logs
	@echo "🧩 Running run_as_root harness"
	@$(run_as_root) bash $(INSTALL_PATH)/test_run_as_root.sh

.PHONY: headscale-stack
headscale-stack: \
	headscale \
	headscale-users \
	headscale-acls
	@echo "🧠 Headscale control plane ready"

.PHONY: tailscaled

tailscaled: \
	headscale-stack \
	tailscaled-lan \
	enable-tailscaled \
	start-tailscaled \
	tailscaled-status
	@COMMIT_HASH=$$(git -C $(REPO_ROOT) rev-parse --short HEAD); \
		echo "🧬 Completed tailscaled orchestration at commit $$COMMIT_HASH"

.PHONY: install-nft-apply nft-apply nft-confirm nft-install nft-status nft-install nft-verify nft-install-rollback
.NOTPARALLEL: nft-confirm nft-apply

install-nft-apply:
	@$(run_as_root) install -o root -g root -m 0755 $(REPO_ROOT)/scripts/homelab-nft-apply.sh $(INSTALL_PATH)/homelab-nft-apply.sh

nft-sync:
	@echo "🔄 Syncing homelab.nft ruleset"
	@$(call install_file,$(REPO_ROOT)/scripts/homelab.nft,$(HOMELAB_NFT_RULESET),root,root,0644)

nft-apply: install-nft-apply nft-sync
	@$(run_as_root) sh -c '\
		echo "🔧 Applying nftables ruleset"; \
		$(INSTALL_PATH)/homelab-nft-apply.sh >/dev/null 2>&1 || true; \
		sha256sum "$(HOMELAB_NFT_RULESET)" | awk "{print \$$1}" > "$(HOMELAB_NFT_HASH_FILE)"; \
		echo "📄 Recorded nftables ruleset hash"; \
	'

nft-confirm:
	@$(run_as_root) $(INSTALL_PATH)/homelab-nft-confirm.sh

nft-install: install-nft-apply
	@$(run_as_root) sh -c '\
		echo "🛡️ Installing homelab nftables firewall"; \
		install -o root -g root -m 0755 $(REPO_ROOT)/scripts/homelab-nft-confirm.sh $(INSTALL_PATH)/homelab-nft-confirm.sh; \
		install -o root -g root -m 0755 $(REPO_ROOT)/scripts/homelab-nft-rollback.sh $(INSTALL_PATH)/homelab-nft-rollback.sh; \
		install -o root -g root -m 0644 $(REPO_ROOT)/config/systemd/homelab-nft.service /etc/systemd/system/homelab-nft.service; \
		install -o root -g root -m 0644 $(REPO_ROOT)/config/systemd/homelab-nft-rollback.service /etc/systemd/system/homelab-nft-rollback.service; \
		install -o root -g root -m 0644 $(REPO_ROOT)/config/systemd/homelab-nft-rollback.timer /etc/systemd/system/homelab-nft-rollback.timer; \
		systemctl daemon-reload >/dev/null 2>&1; \
		systemctl enable homelab-nft.service homelab-nft-rollback.timer >/dev/null 2>&1 || true; \
		echo "✅ Firewall units installed (not yet applied)"; \
	'

nft-status:
	@$(run_as_root) nft list table inet homelab_filter

nft-install-rollback:
	@$(run_as_root) sh -c '\
		echo "⏪ Installing homelab nft rollback units"; \
		install -o root -g root -m 0644 $(REPO_ROOT)/config/systemd/homelab-nft-rollback.service /etc/systemd/system/homelab-nft-rollback.service; \
		install -o root -g root -m 0644 $(REPO_ROOT)/config/systemd/homelab-nft-rollback.timer /etc/systemd/system/homelab-nft-rollback.timer; \
		systemctl daemon-reload >/dev/null 2>&1; \
		systemctl enable homelab-nft-rollback.timer >/dev/null 2>&1 || true; \
		echo "✅ nft rollback units installed"; \
	'

# The root of the DAG
.PHONY: homelab-all
homelab-all: \
	sanity \
	repo-preflight \
	nft-apply-phase \
	router-install-scripts \
	wg-network-phase \
	service-phase \
	router-health \
	verify-ipv6-invariants
	@echo "🎉 Homelab fully converged."

router-install-scripts: | repo-preflight

# Phase 1: Security/Firewall (Foundational, must run sequentially)
.PHONY: nft-apply-phase
nft-apply-phase: nft-install nft-apply nft-confirm

# Phase 2: Network Infrastructure (Parallel branches)
.PHONY: wg-network-phase
wg-network-phase: | nft-confirm
wg-network-phase: converge-network router-ra-policy tailscaled-dependencies-met wg-up
wg-network-phase: nft-apply-phase

# Phase 3: Services (Independent of each other)
.PHONY: service-phase
service-phase: | nft-confirm
service-phase: install-systemd enable-systemd deploy-unbound-config monitoring \
			install-router-prefix-watchdog install-nas-prefix-watchdog \
			enable-unbound verify-internal-dns all-remote \
			router-certs-prepare \
			router-certs-deploy \
			router-caddy
service-phase: wg-network-phase

# Sub-groupings
tailscaled-dependencies-met: headscale-stack tailscaled

# Force sequential order only where necessary using order-only prerequisites (|)
# Example: Ensure nft is confirmed BEFORE we touch WireGuard
wg-install-router: | nft-confirm
wg-up-nas: | nft-confirm
