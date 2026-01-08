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
include mk/00_prereqs.mk
#include mk/01_common.mk
include mk/05_bootstrap_wireguard.mk
include mk/10_groups.mk      # group membership enforcement (security bootstrap)
include mk/20_deps.mk        # package dependencies (apt installs, base tools)
include mk/30_config_validation.mk
include mk/30_generate.mk    # generation helpers (cert/key creation, QR codes)
#include mk/31_setup-subnet-router.mk # Subnet router orchestration LEGACY — DO NOT USE Superseded by homelab-nft.service + homelab.nft
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
include mk/70_dnscrypt-proxy.mk   # dnscrypt-proxy setup and deployment
include mk/70_apt_proxy_auto.mk
include mk/80_tailnet.mk     # Tailscale/Headscale orchestration
include mk/81_headscale.mk              # Headscale service + binary + systemd
include mk/83_headscale-users.mk        # Users (future)
include mk/84_headscale-acls.mk         # ACLs (future)
include mk/85_tailscaled.mk  # tailscaled client management (ACLs, ephemeral keys, systemd units, status/logs)
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
	@echo "  Firewall (nftables):"
	@echo "    make nft-install        # Install firewall scripts and systemd units"
	@echo "    make nft-apply          # Apply firewall rules (arms rollback timer)"
	@echo "    make nft-confirm        # Confirm firewall rules (disarms rollback)"
	@echo "    make nft-status         # Show active homelab firewall rules"
	@echo "  Package and preflight"
	@echo "	   make prereqs            # Install prerequisite tools (curl, jq, git, nftables, ndppd, dns utils, admin helpers)"
	@echo "    make deps               # Install developer tooling (go, pandoc, checkmake, strace, vnstat)"
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
	@echo "  Tailnet / Headscale"
	@echo "    make headscale-stack          # Ensure Headscale service, namespaces, users, and ACLs"
	@echo "    make tailscaled               # Full Tailscale orchestration (LAN role by default)"
	@echo "    make tailscaled-lan           # Enroll this host as LAN-capable node (exit-node + subnet)"
	@echo "    make tailscaled-wan           # Enroll this host as WAN-only node (internet access)"
	@echo "    make tailscaled-status        # Show tailscaled health, traffic, and versions"
	@echo "    make tailscaled-logs          # Tail tailscaled + role unit logs"
	@echo ""
	@echo "  WireGuard (recommended workflow)"
	@echo "    make wg                     # Apply intent (if changed) + show full status"
	@echo "    make wg-apply               # Compile + deploy only"
	@echo "    make wg-status              # Quick runtime summary"
	@echo "    make wg-runtime             # Detailed runtime view"
	@echo ""
	@echo "  WireGuard (client operations)"
	@echo "    make wg-show BASE=<b> IFACE=<wgX>   # Show client config + QR"
	@echo "    make wg-qr   BASE=<b> IFACE=<wgX>   # Show QR only"
	@echo "    make wg-remove-client BASE=<b> IFACE=<wgX>"
	@echo ""
	@echo "  WireGuard (⚠️  DESTRUCTIVE OPERATIONS ⚠️)"
	@echo "                                   # Use ONLY when fixing structural config or rotating keys"
	@echo "    make wg-rebuild-all            # FULL rebuild: stop WG, wipe configs + keys, regenerate, deploy"
	@echo "    make wg-reinstall-all          # DESTRUCTIVE: wipe and recreate WG state (interactive)"
	@echo "                                   #     - Rotates ALL server keys"
	@echo "                                   #     - Invalidates ALL existing clients"
	@echo "                                   #     - Rebuilds from authoritative CSV"
	@echo "                                   #     - Requires explicit confirmation delay"
	@echo ""
	@echo "    Authoritative input:"
	@echo "      /volume1/homelab/wireguard/input/clients.csv"
	@echo "      (user,machine,iface ; comments allowed with '#')"
	@echo ""
	@echo "    Profiles (by iface):"
	@echo "      wg6 = WAN-only IPv4+IPv6, DNS via WG interface (Swiss TV)"
	@echo "      wg7 = Full access (LAN + WAN IPv4/IPv6)"
	@echo ""
	@echo "  WireGuard (low-level / legacy helpers)"
	@echo "    make wg0 .. wg7                 # Ensure server config and keys for wg0 through wg7"
	@echo "    make wg-up-<N>                  # Bring up wgN (idempotent), e.g. make wg-up-7"
	@echo "    make wg-down-<N>                # Bring down wgN (idempotent)"
	@echo "    make wg-add-peers               # Program peers from generated client configs"
	@echo "    make wg-clean-<N>               # Revoke all clients bound to wgN (destructive)"
	@echo "    make wg-clean-list-<N>          # Preview files that would be removed for wgN"
	@echo "    make all-wg                     # Ensure all wgN configs (wg0..wg7)"
	@echo "    make all-wg-up                  # Bring up all wg interfaces"
	@echo "    make wg-reinstall-all           # LEGACY: destructive WG reset (superseded by wg-rebuild-all)"
	@echo ""
	@echo "  Client management"
	@echo "    make client-<name>              # Generate client config (name may include -wgN or use IFACE=wgN)"
	@echo "    make client-list                # List client artifacts (*.conf, *.key, *.pub)"
	@echo "    make client-clean-<name>        # Revoke a single client (backup + remove runtime peer)"
	@echo "    make client-showqr-<name>       # Show QR for client (auto-create if missing)"
	@echo "    make all-clients-generate       # Generate clients from authoritative CSV (compiled plan)"
	@echo "    make client-dashboard           # Emoji table of users/machines vs interfaces"
	@echo ""
	@echo "  DNS"
	@echo "    make dns-stack                  # Install + configure dnsmasq + Unbound (split-horizon baseline)"
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
	@echo "  - Authoritative intent lives in:"
	@echo "      /volume1/homelab/wireguard/input/clients.csv"
	@echo "  - This file is the ONLY human-edited input; everything else is derived."
	@echo "  - Validation failures never modify deployed state (last-known-good remains active)."
	@echo "  - Direct editing of /etc/wireguard is unsupported and will be overwritten."
	@echo "  - Direct client generation targets remain available for emergency/manual use."
	@echo ""
	@echo "[make] WireGuard bootstrap:"
	@echo "  See header comments in:"
	@echo "    /volume1/homelab/wireguard/input/clients.csv"
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
	@git -C $(HOMELAB_DIR) pull --rebase || true
	@echo "[make] Repo now at commit $$(git -C $(HOMELAB_DIR) rev-parse --short HEAD)"

.PHONY: all gen0 gen1 gen2 deps install-go remove-go install-checkmake remove-checkmake
.PHONY: setup-subnet-router
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

# --- all targets (legacy) ---
all: harden-groups gitcheck gen0 gen1 gen2
	@echo "[make] Completed full orchestration (harden-groups → gen0 → gen1 → gen2)"

# -- all targets
.PHONY: bootstrap
bootstrap: \
	deps \
	vpn-stack \
	dns-stack \
	dns-runtime
	@echo "Consider make firewall-stack"

.PHONY: firewall-stack
firewall-stack: \
	install-pkg-nftables \
	enable-ndppd \
	nft-install
	@echo "[make] Firewall stack installed." 
	@echo "[make] Run 'make nft-apply' to activate the firewall."

.PHONY: dns-stack
dns-stack: \
	install-pkg-dnsmasq \
	deploy-dnsmasq-config \
	enable-unbound \
	dnsdist \
	dns-runtime

.PHONY: vpn-stack
vpn-stack: \
	install-pkg-wireguard \
	install-pkg-tailscale

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

# --- Gen0: foundational services --- disabled: dnscrypt-proxy
gen0: \
	sysctl \
	harden-groups \
	ensure-known-hosts \
	setup-subnet-router \
	headscale-stack \
	tailscaled \
	dns-stack \
	dns-runtime
	@echo "[make] Running gen0 foundational services..."

gen1: caddy tailnet rotate wg-baseline code-server

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

.PHONY: nft-apply nft-confirm nft-install nft-status

nft-apply:
	sudo scripts/homelab-nft-apply.sh

nft-confirm:
	sudo scripts/homelab-nft-confirm.sh

.PHONY: nft-install nft-apply nft-confirm nft-status

.PHONY: nft-install
nft-install:
	@echo "[make] Installing homelab nftables firewall..."
	@$(run_as_root) install -o root -g root -m 0755 \
		$(HOMELAB_DIR)/scripts/homelab-nft-apply.sh /usr/local/bin/homelab-nft-apply.sh
	@$(run_as_root) install -o root -g root -m 0755 $(HOMELAB_DIR)/scripts/homelab-nft-confirm.sh \
		/usr/local/bin/homelab-nft-confirm.sh
	@$(run_as_root) install -o root -g root -m 0755 $(HOMELAB_DIR)/scripts/homelab-nft-rollback.sh \
		/usr/local/bin/homelab-nft-rollback.sh
	@$(run_as_root) install -o root -g root -m 0644 $(HOMELAB_DIR)/config/systemd/homelab-nft.service \
		/etc/systemd/system/homelab-nft.service
	@$(run_as_root) install -o root -g root -m 0644 $(HOMELAB_DIR)/config/systemd/homelab-nft-rollback.timer \
		/etc/systemd/system/homelab-nft-rollback.timer
	@$(run_as_root) systemctl daemon-reload
	@$(run_as_root) systemctl enable homelab-nft.service homelab-nft-rollback.timer
	@echo "[make] ✅ Firewall units installed (not yet applied)"
	@echo "[make] Next steps:"
	@echo "[make]   make nft-apply    # Apply firewall rules (arms rollback timer)"
	@echo "[make]   make nft-confirm  # Confirm rules (disarms rollback)"
	@echo "[make]   (If not confirmed, rollback runs automatically)"


nft-status:
	sudo nft list table inet homelab_filter

.PHONY: nft-install-rollback
nft-install-rollback:
	@echo "[make] Installing homelab nft rollback units..."
	@$(run_as_root) install -o root -g root -m 0644 $(HOMELAB_DIR)/config/systemd/homelab-nft-rollback.service \
		/etc/systemd/system/homelab-nft-rollback.service @$(run_as_root) install -o root -g root -m 0644 \
		$(HOMELAB_DIR)/config/systemd/homelab-nft-rollback.timer /etc/systemd/system/homelab-nft-rollback.timer
	@$(run_as_root) systemctl daemon-reload
	@$(run_as_root) systemctl enable homelab-nft-rollback.timer


