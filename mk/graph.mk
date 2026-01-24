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

HOMELAB_REPO := git@github.com:Jambo15/homelab.git

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

# --- Includes (ordered by prefix) ---
include mk/00_sanity.mk
include mk/00_prereqs.mk
include mk/01_common.mk
include mk/05_bootstrap_wireguard.mk
include mk/10_groups.mk      # group membership enforcement (security bootstrap)
include mk/20_deps.mk        # package dependencies (apt installs, base tools)
include mk/20_net-tunnel.mk
include mk/20_sysctl.mk
include mk/30_config_validation.mk
include mk/40_acme.mk        # ACME client orchestration (Let's Encrypt, etc.)
include mk/40_code-server.mk
include mk/40_wireguard.mk   # Wireguard orchestration
include mk/41_wireguard-status.mk
include mk/42_wireguard-qr.mk
include mk/43_wireguard-runtime.mk
include mk/40_caddy.mk
include mk/50_certs.mk       # certificate handling (issue, renew, deploy)
include mk/50_dnsmasq.mk
include mk/60_unbound.mk     # Unbound DNS resolver setup
include mk/65_dnsmasq.mk     # DNS forwarding requests to Unbound
include mk/70_dnsdist.mk     #
include mk/71_dns-warm.mk    # DNS cache warming (systemd timer)
include mk/70_apt_proxy_auto.mk
include mk/80_tailnet.mk     # Tailscale/Headscale orchestration
include mk/81_headscale.mk              # Headscale service + binary + systemd
include mk/83_headscale-users.mk        # Users (future)
include mk/84_headscale-acls.mk         # ACLs (future)
include mk/85_monitoring.mk
include mk/85_tailscaled.mk  # tailscaled client management (ACLs, ephemeral keys, systemd units, status/logs)
include mk/90_dns-health.mk  # DNS health checks and monitoring
include mk/90_converge.mk
include mk/95_status.mk
include mk/99_lint.mk        # lint and safety checks (always last)

# ============================================================
# Makefile — homelab certificate orchestration
# ============================================================

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
		mkdir -p $(dir $(HOMELAB_DIR)); \
		git clone $(HOMELAB_REPO) $(HOMELAB_DIR); \
	else \
		echo "[make] homelab repo already present at $(HOMELAB_DIR)"; \
		git -C $(HOMELAB_DIR) rev-parse --short HEAD; \
	fi

update: gitcheck
	@echo "[make] Updating homelab repo..."
	@git -C $(HOMELAB_DIR) pull --rebase || true
	@echo "[make] Repo now at commit $$(git -C $(HOMELAB_DIR) rev-parse --short HEAD)"

.PHONY: all gen0 gen1 gen2 deps install-go remove-go install-checkmake remove-checkmake
.PHONY: test logs clean-soft

.PHONY: clean
clean:
	@echo "[make] Removing tailscaled role units..."
	@$(run_as_root) systemctl disable tailscaled-lan.service tailscaled || true
	@$(run_as_root) rm -f /etc/systemd/system/tailscaled-lan.service || true
	@$(run_as_root) systemctl daemon-reload
	@echo "[make] ✅ Cleaned tailscaled units and disabled services"

.PHONY: reload
reload:
	@$(run_as_root) systemctl daemon-reload
	@echo "[make] 🔄 systemd reloaded"

.PHONY: restart
restart:
	@$(run_as_root) systemctl restart tailscaled tailscaled-lan.service
	@echo "[make] 🔁 Restarted tailscaled + family + guest services"

test: logs
	@echo "[make] Running run_as_root harness..."
	@$(run_as_root) bash $(HOMELAB_DIR)/scripts/test_run_as_root.sh

# all:
# - Enforces invariants
# - Converges kernel + firewall + DNS + WireGuard
# - Brings up tailnet control plane (Headscale + tailscaled)
# - Enables baseline observability (Prometheus)
.PHONY: all
all: assert-sanity converge-network wg tailscaled monitoring
	echo ""; \
	echo "🎉 Homelab fully converged"; \
	echo "   - Network + WireGuard ready"; \
	echo "   - Tailnet control plane active"; \
	echo "   - Monitoring online"

.PHONY: headscale-stack
headscale-stack: \
	headscale \
	headscale-users \
	headscale-acls
	@echo "[make] Headscale control plane ready"

.PHONY: tailscaled

tailscaled: \
	headscale-stack \
	tailscaled-lan \
	enable-tailscaled \
	start-tailscaled \
	tailscaled-status
	@COMMIT_HASH=$$(git -C $(HOMELAB_DIR) rev-parse --short HEAD); \
		echo "[make] Completed tailscaled orchestration at commit $$COMMIT_HASH"

.PHONY: wg

wg: wg-apply wg-intent wg-dashboard wg-status wg-runtime wg-clients

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

.PHONY: nft-apply nft-confirm nft-install nft-status nft-install nft-verify nft-install-rollback
.NOTPARALLEL: nft-confirm nft-apply

nft-apply:
	@$(run_as_root) scripts/homelab-nft-apply.sh
	@echo "🧾 Recording applied nftables ruleset hash"
	@$(run_as_root) sh -c 'sha256sum "$(HOMELAB_NFT_RULESET)" | awk "{print \$$1}" > "$(HOMELAB_NFT_HASH_FILE)"'

nft-confirm:
	sudo scripts/homelab-nft-confirm.sh

nft-install:
	@echo "[make] Installing homelab nftables firewall..."
	@$(run_as_root) install -o root -g root -m 0755 $(HOMELAB_DIR)/scripts/homelab-nft-apply.sh /usr/local/bin/homelab-nft-apply.sh
	@$(run_as_root) install -o root -g root -m 0755 $(HOMELAB_DIR)/scripts/homelab-nft-confirm.sh /usr/local/bin/homelab-nft-confirm.sh
	@$(run_as_root) install -o root -g root -m 0755 $(HOMELAB_DIR)/scripts/homelab-nft-rollback.sh /usr/local/bin/homelab-nft-rollback.sh
	@$(run_as_root) install -o root -g root -m 0644 $(HOMELAB_DIR)/config/systemd/homelab-nft.service /etc/systemd/system/homelab-nft.service
	@$(run_as_root) install -o root -g root -m 0644 $(HOMELAB_DIR)/config/systemd/homelab-nft-rollback.service /etc/systemd/system/homelab-nft-rollback.service
	@$(run_as_root) install -o root -g root -m 0644 $(HOMELAB_DIR)/config/systemd/homelab-nft-rollback.timer /etc/systemd/system/homelab-nft-rollback.timer
	@$(run_as_root) systemctl daemon-reload
	@$(run_as_root) systemctl enable homelab-nft.service homelab-nft-rollback.timer
	@echo "[make] ✅ Firewall units installed (not yet applied)"
	@echo "[make] Next steps:"
	@echo "[make]   make nft-apply    # Apply firewall rules (arms rollback timer)"
	@echo "[make]   make nft-confirm  # Confirm rules (disarms rollback)"
	@echo "[make]   (If not confirmed, rollback runs automatically)"

nft-status:
	sudo nft list table inet homelab_filter

nft-install-rollback:
	@echo "[make] Installing homelab nft rollback units..."
	@$(run_as_root) install -o root -g root -m 0644 $(HOMELAB_DIR)/config/systemd/homelab-nft-rollback.service \
		/etc/systemd/system/homelab-nft-rollback.service @$(run_as_root) install -o root -g root -m 0644 \
		$(HOMELAB_DIR)/config/systemd/homelab-nft-rollback.timer /etc/systemd/system/homelab-nft-rollback.timer
	@$(run_as_root) systemctl daemon-reload
	@$(run_as_root) systemctl enable homelab-nft-rollback.timer

#DEBUG
print-debug:
	@echo "CURDIR=$(CURDIR)"
	@echo "MAKEFILE_LIST=$(MAKEFILE_LIST)"
	@echo "HOMELAB_DIR=$(HOMELAB_DIR)"

.PHONY: regen-clients
regen-clients: ensure-run-as-root
	@echo "🔁 Regenerating all WireGuard clients from authoritative input"
	@$(run_as_root) env WG_ROOT="$(WG_ROOT)" \
		"$(HOMELAB_DIR)/scripts/wg-compile-clients.sh"


