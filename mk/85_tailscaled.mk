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

SYSTEMD_SRC_DIR ?= /home/julie/src/homelab/config/systemd
SYSTEMD_DST_DIR ?= /etc/systemd/system

.PHONY: tailscaled-check-deps \
	tailscaled-lan tailscaled-wan \
	enable-tailscaled start-tailscaled stop-tailscaled \
	tailscaled-status tailscaled-logs tailscale-check

# --------------------------------------------------------------------
# Verify dependencies (fail fast)
# --------------------------------------------------------------------
tailscaled-check-deps:
	@command -v jq >/dev/null 2>&1 || { echo "❌ jq not installed"; exit 1; }
	@command -v xargs >/dev/null 2>&1 || { echo "❌ xargs not installed"; exit 1; }
	@command -v $(TS_BIN) >/dev/null 2>&1 || { echo "❌ tailscale not found"; exit 1; }
	@command -v $(HS_BIN) >/dev/null 2>&1 || { echo "❌ headscale not found"; exit 1; }

# --------------------------------------------------------------------
# LAN client (trusted: LAN + exit-node)
# --------------------------------------------------------------------
tailscaled-lan: tailscaled-check-deps
	@echo "🔑 Enrolling LAN client (bardi-lan / lan)"
	@$(run_as_root) $(TS_BIN) up --reset \
		--login-server=https://vpn.bardi.ch \
		--authkey=$$($(run_as_root) $(HS_BIN) preauthkeys create \
			--user $(HS_USER_LAN) \
			--ephemeral=false \
			--reusable=false \
			--output json | jq -r '.key') \
		--advertise-exit-node \
		--advertise-routes=10.89.12.0/24 \
		--accept-dns=true \
		--accept-routes=true
	@echo "📡 LAN exit-node + subnet route advertised"
	@$(run_as_root) $(TS_BIN) status --json | jq '.Self.Capabilities'
	@echo "✅ LAN client configured"

# --------------------------------------------------------------------
# WAN client (internet-only)
# --------------------------------------------------------------------
tailscaled-wan: tailscaled-check-deps
	@echo "🔑 Enrolling WAN client (bardi-wan / wan)"
	@$(run_as_root) $(TS_BIN) up --reset \
		--login-server=https://vpn.bardi.ch \
		--authkey=$$($(run_as_root) $(HS_BIN) preauthkeys create \
			--user $(HS_USER_WAN) \
			--ephemeral=true \
			--reusable=false \
			--output json | jq -r '.key') \
		--accept-dns=true
	@echo "✅ WAN client configured (internet-only)"

# --------------------------------------------------------------------
# Install and enable services at boot
# --------------------------------------------------------------------
enable-tailscaled:
	@echo "🧩 Installing systemd role units"
	@$(run_as_root) install -o root -g root -m 644 \
		$(SYSTEMD_SRC_DIR)/tailscaled-lan.service \
		$(SYSTEMD_DST_DIR)/tailscaled-lan.service
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
	@echo "   CLI:"; $(TS_BIN) version || true
	@echo "   Daemon:"; $(run_as_root) tailscaled --version || true

tailscaled-logs:
	@echo "📜 Tailing logs (Ctrl-C to exit)"
	@$(run_as_root) journalctl -u tailscaled -u tailscaled-lan.service -f

tailscale-check:
	@echo "🔎 Checking Tailscale versions"
	@echo "CLI:"; $(TS_BIN) version || true
	@echo "Daemon:"; $(run_as_root) tailscaled --version || true
