# --------------------------------------------------------------------
# mk/85_tailscaled.mk — tailscaled client management
# --------------------------------------------------------------------
# CONTRACT:
# - Provides service-specific recipes for tailscaled:
#   * ephemeral key onboarding (LAN / WAN roles)
#   * systemd unit install/enable
#   * status + logs
# - ACLs are managed exclusively by mk/84_headscale-acls.mk
# - Users and namespaces must already exist.
# - Recipes must remain operator-safe: no secrets written to disk,
#   ephemeral+non-reusable keys only, safe file ownership/permissions.
# --------------------------------------------------------------------

TAILSCALE_KEYRING := /usr/share/keyrings/tailscale-archive-keyring.gpg
TAILSCALE_KEY_URL := https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg

TAILSCALE_REPO_FILE := /etc/apt/sources.list.d/tailscale.list
TAILSCALE_REPO_LINE := deb [signed-by=$(TAILSCALE_KEYRING)] https://pkgs.tailscale.com/stable/debian bookworm main

TS_BIN ?= /usr/bin/tailscale
HS_BIN ?= /usr/local/bin/headscale

define headscale_user_id
$(shell [ -x "$(HS_BIN)" ] && command -v jq >/dev/null 2>&1 && \
	$(run_as_root) "$(HS_BIN)" users list --output json \
	| jq -r '.[] | select(.name=="$(1)") | .id' || true)
endef

# Headscale users (namespaces already enforced upstream)
HS_USER_LAN := $(call headscale_user_id,lan)
HS_USER_WAN := $(call headscale_user_id,wan)

SYSTEMD_SRC_DIR := $(MAKEFILE_DIR)config/systemd

.PHONY: tailscaled-check-deps \
	tailscaled-lan tailscaled-wan \
	enable-tailscaled start-tailscaled stop-tailscaled \
	tailscaled-status tailscaled-logs tailscale-check

# --------------------------------------------------------------------
# Verify dependencies (fail fast)
# --------------------------------------------------------------------
tailscaled-check-deps:
	@for c in jq xargs $(TS_BIN) $(HS_BIN); do \
		command -v $$c >/dev/null 2>&1 || { echo "❌ $$c not found"; exit 1; }; \
	done

.NOTPARALLEL: tailscaled-lan tailscaled-wan
# --------------------------------------------------------------------
# LAN client (trusted: LAN + exit-node)
# --------------------------------------------------------------------
# do not use --accept-dns=true as it hijacks DNS entries in /etc/resolv.conf
tailscaled-lan: tailscaled-check-deps net-tunnel-preflight
	$(call warn_if_no_net_tunnel_preflight)
	@echo "🔑 Enrolling LAN client (bardi-lan / lan)"
	@$(run_as_root) $(TS_BIN) up --reset \
		--login-server=https://vpn.bardi.ch \
		--authkey=$$($(run_as_root) $(HS_BIN) preauthkeys create \
			--user $(HS_USER_LAN) \
			--output json | jq -r '.key') \
		--advertise-exit-node \
		--advertise-routes=10.89.12.0/24 \
		--accept-dns=false \
		--accept-routes=true
	@echo "📡 LAN exit-node + subnet route advertised"
	@$(run_as_root) $(TS_BIN) status --json | jq '.Self.CapMap'
	@echo "✅ LAN client configured"

# --------------------------------------------------------------------
# WAN client (internet-only)
# --------------------------------------------------------------------
tailscaled-wan: tailscaled-check-deps
	$(call warn_if_no_net_tunnel_preflight)
	@echo "🔑 Enrolling WAN client (bardi-wan / wan)"
	@$(run_as_root) $(TS_BIN) up --reset \
		--login-server=https://vpn.bardi.ch \
		--authkey=$$($(run_as_root) $(HS_BIN) preauthkeys create \
			--user $(HS_USER_WAN) \
			--ephemeral=true \
			--output json | jq -r '.key') \
		--accept-dns=false
	@echo "✅ WAN client configured (internet-only)"

# --------------------------------------------------------------------
# Install and enable services at boot
# --------------------------------------------------------------------
enable-tailscaled:
	@echo "🧩 Installing systemd role units"
	@$(run_as_root) install -o root -g root -m 644 \
		$(SYSTEMD_SRC_DIR)/tailscaled-lan.service \
		$(SYSTEMD_DIR)/tailscaled-lan.service
	@$(run_as_root) systemctl daemon-reload
	@$(run_as_root) systemctl enable tailscaled tailscaled-lan.service
	@echo "🚀 Enabled at boot: tailscaled + role service"

# --------------------------------------------------------------------
# Runtime control
# --------------------------------------------------------------------
start-tailscaled:
	@$(run_as_root) systemctl start tailscaled tailscaled-lan.service
	@echo "▶️ Started: tailscaled + role service"

stop-tailscaled:
	@$(run_as_root) systemctl stop tailscaled tailscaled-lan.service
	@echo "⏹️ Stopped: tailscaled + role service"

# --------------------------------------------------------------------
# Status and logs
# --------------------------------------------------------------------
tailscaled-status: install-pkg-vnstat
	@echo "🔎 tailscaled health + stats"
	@echo "🟢 daemon:"; $(run_as_root) systemctl is-active tailscaled || echo "❌ inactive"
	@echo "🧩 role unit:"; $(run_as_root) systemctl is-enabled tailscaled-lan.service || echo "❌ not enabled"
	@echo "📡 connected nodes:"; $(run_as_root) $(TS_BIN) status | awk '{print $$1, $$2, $$3}'
	@echo "📊 monthly traffic:"; vnstat -i tailscale0 -m || true
	@echo "⚡ connection events (1h):"; \
		$(run_as_root) journalctl -u tailscaled --since "1 hour ago" \
		| grep -i connection | wc -l | xargs echo "events"
	@echo "🧾 versions:"
	@echo "	CLI:"; $(TS_BIN) version || true
	@echo "	Daemon:"; $(run_as_root) tailscaled --version || true

tailscaled-logs:
	@echo "📜 Tailing logs (Ctrl-C to exit)"
	@$(run_as_root) journalctl -u tailscaled -u tailscaled-lan.service -f

tailscale-check:
	@echo "🔎 Checking Tailscale versions"
	@echo "CLI:"; $(TS_BIN) version || true
	@echo "Daemon:"; $(run_as_root) tailscaled --version || true
