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
include $(REPO_ROOT)/mk/00_icons.mk
include $(REPO_ROOT)/mk/00_prereqs.mk
include $(REPO_ROOT)/mk/01_core.mk
include $(REPO_ROOT)/mk/10_stamps_prompt.mk
include $(REPO_ROOT)/mk/10_stamps.mk
include mk/common/core.mk
include mk/common/scripts.mk
include mk/common/macros.mk

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
include $(REPO_ROOT)/mk/pve/network.mk

# Step 5 — Everything else
include $(REPO_ROOT)/mk/05_bootstrap_acme.mk
include $(REPO_ROOT)/mk/10_bootstrap_security.mk
include $(REPO_ROOT)/mk/10_groups.mk
include $(REPO_ROOT)/mk/10_local-tools.mk
include $(REPO_ROOT)/mk/11_permissions.mk
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
#include $(REPO_ROOT)/mk/40_nas-traefik.mk
include $(REPO_ROOT)/mk/netbird.mk
# STAMP_DIR_ROOT must be defined before any WG DAG fragments are included
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
	@echo " Next Step: make all"
	@echo "------------------------------------------------------------"

# ============================================================
# Makefile — homelab certificate orchestration
# ============================================================

# --------------------------------------------------------------------

.PHONY: all gen0 gen1 gen2 deps install-go remove-go install-checkmake remove-checkmake
.PHONY: logs clean-soft

.PHONY: test
test: logs
	@echo "🔧 Running run_as_root harness"
	@$(run_as_root) bash $(INSTALL_PATH)/test_run_as_root.sh

.PHONY: headscale-stack
headscale-stack: \
	headscale \
	headscale-users \
	headscale-acls
	@echo "🔧 Headscale control plane ready"

.PHONY: tailscaled

tailscaled: \
	headscale-stack \
	tailscaled-lan \
	enable-tailscaled \
	start-tailscaled \
	tailscaled-status
	@COMMIT_HASH=$$(git -C $(REPO_ROOT) rev-parse --short HEAD); \
		echo "🔧 Completed tailscaled orchestration at commit $$COMMIT_HASH"


# The root of the DAG
.PHONY: homelab-all
homelab-all: router-health verify-ipv6-invariants
	@echo "🎉 Homelab fully converged."

# Enforce strict DAG sequencing for parallel execution (-j)
verify-ipv6-invariants: service-phase
router-health: service-phase
service-phase: wg-network-phase
wg-network-phase: \
	enforce-groups \
	enforce-homelab-perms \
	enforce-wireguard-input \
	sanity \
	repo-preflight \
	nft-apply-phase \
	router-install-scripts \
	install-router-prefix-watchdog \
	install-nas-prefix-watchdog

# Phase 1: Security/Firewall (Foundational, must run sequentially)
.PHONY: nft-apply-phase
nft-apply-phase: nft-install nft-apply nft-confirm

# Phase 2: Network Infrastructure (Parallel branches)
.PHONY: wg-network-phase
wg-network-phase: enforce-wireguard-input
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
			router-caddy \
			nas-caddy \
			netbird-deploy
service-phase: wg-network-phase

# Sub-groupings
tailscaled-dependencies-met: headscale-stack tailscaled

# Force sequential order only where necessary using order-only prerequisites (|)
# Example: Ensure nft is confirmed BEFORE we touch WireGuard
wg-install-router: | nft-confirm
wg-up-nas: | nft-confirm