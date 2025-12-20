# --------------------------------------------------------------------
# mk/82_tailscaled.mk — tailscaled client management
# --------------------------------------------------------------------
# CONTRACT:
# - Provides service-specific recipes for tailscaled:
#   * ACL install
#   * ephemeral key onboarding (family)
#   * systemd unit install/enable
#   * status + logs
# - Does NOT define global lifecycle targets (clean, reload, restart).
#   Those are centralized in the root Makefile to cover all services.
# - Recipes must remain operator-safe: no secrets written to disk,
#   ephemeral+non-reusable keys only, safe file ownership/permissions.
# --------------------------------------------------------------------
TS_BIN      ?= /usr/bin/tailscale
HS_BIN      ?= /usr/bin/headscale

define headscale_user_id
$(shell [ -x "$(HS_BIN)" ] && command -v jq >/dev/null 2>&1 && sudo "$(HS_BIN)" users list --output json \
	| jq -r '.[] | select(.name=="$(1)") | .id' || true)
endef

HS_USER_FAM = $(call headscale_user_id,bardi-family)
HS_USER_GUE = $(call headscale_user_id,bardi-guests)
ACL_SRC     ?= /home/julie/src/homelab/config/headscale/acl.json
ACL_DST     ?= /etc/headscale/acl.json
SYSTEMD_SRC_DIR ?= /home/julie/src/homelab/config/systemd
SYSTEMD_DST_DIR ?= /etc/systemd/system

.PHONY: check-deps acl-install tailscaled-family \
		enable-tailscaled start-tailscaled tailscaled-status tailscaled-logs

# Verify dependencies (fail fast)
check-deps:
	@command -v jq >/dev/null 2>&1 || { echo "❌ jq not installed"; exit 1; }
	@command -v xargs >/dev/null 2>&1 || { echo "❌ xargs not installed"; exit 1; }
	@command -v $(TS_BIN) >/dev/null 2>&1 || { echo "❌ tailscale not found"; exit 1; }
	@command -v $(HS_BIN) >/dev/null 2>&1 || { echo "❌ headscale not found"; exit 1; }

# Install ACL file safely
acl-install: check-deps
	@echo "📂 Installing ACL file from $(ACL_SRC) to $(ACL_DST)"
	@sudo install -o root -g headscale -m 640 $(ACL_SRC) $(ACL_DST)
	@sudo systemctl restart headscale
	@echo "✅ ACL deployed (owner=root, group=headscale, mode=640) and headscale restarted."

# Bring up tailscaled for family (LAN + exit node), no manual re-enroll after every reboot -> --ephemeral=false
tailscaled-family: acl-install
	@echo "🔑 Creating ephemeral one-time key for bardi-family (ID: $(HS_USER_FAM)) and consuming it for exit-node"
	@sudo $(TS_BIN) up --reset \
		--login-server=https://vpn.bardi.ch \
		--authkey=$$(sudo $(HS_BIN) preauthkeys create --user $(HS_USER_FAM) --ephemeral=false --reusable=false --output json | jq -r '.key') \
		--advertise-exit-node \
		--advertise-routes=10.89.12.0/24 \
		--accept-dns=true \
		--accept-routes=true
	@echo "📡 Exit node advertised: LAN 10.89.12.0/24 + DNS accepted | Commit=$$(git -C ~/src/homelab rev-parse --short HEAD) | Timestamp=$$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	@echo "📡 Verifying capabilities..."
	@sudo $(TS_BIN) status --json | jq '.Self.Capabilities'
	@echo "✅ Family node configured: exit-node + route 10.89.12.0/24"

# Install and enable all services at boot (daemon + family)
enable-tailscaled: acl-install
	@echo "🧩 Installing systemd role units"
	@sudo install -o root -g root -m 644 $(SYSTEMD_SRC_DIR)/tailscaled-family.service $(SYSTEMD_DST_DIR)/tailscaled-family.service
	@sudo systemctl daemon-reload
	@sudo systemctl enable tailscaled tailscaled-family.service
	@echo "🚀 Enabled at boot: tailscaled + family services"

# Start all services immediately
start-tailscaled:
	@sudo systemctl start tailscaled tailscaled-family.service
	@echo "▶️ Started: tailscaled + family services"

# Stop all services immediately
stop-tailscaled:
	@sudo systemctl stop tailscaled tailscaled-family.service
	@echo "⏹️ Stopped: tailscaled + family services"

# Status target: health + operational stats
tailscaled-status: install-pkg-vnstat
	@echo "🔎 tailscaled health + stats"
	@echo "🟢 tailscaled daemon:"; sudo systemctl is-active tailscaled || echo "❌ inactive"
	@echo "👨‍👩‍👧 family service:"; sudo systemctl is-enabled tailscaled-family.service || echo "❌ not enabled"
	@echo "📡 Connected nodes:"; sudo $(TS_BIN) status | awk '{print $$1, $$2, $$3}'
	@echo "📊 Monthly traffic on tailscale0:"; vnstat -i tailscale0 -m || echo "vnstat not installed or no data yet"
	@echo "⚡ Connection events (last hour):"; sudo journalctl -u tailscaled --since "1 hour ago" | grep -i "connection" | wc -l | xargs echo "events"
	@echo "🧾 Version check:"
	@echo "   CLI:"; $(TS_BIN) version || true
	@echo "   Daemon:"; sudo tailscaled --version || true
	@echo "[make] tailscale version check: CLI=$$( $(TS_BIN) version | head -n1 ) DAEMON=$$( sudo tailscaled --version | head -n1 )" | sudo tee /dev/stderr | sudo systemd-cat -t tailscaled-status

# Consolidated logs view
tailscaled-logs:
	@echo "📜 Tailing logs for tailscaled + role services (Ctrl-C to exit)"
	@sudo journalctl -u tailscaled -u tailscaled-family.service -f

tailscale-check:
	@echo "🔎 Checking Tailscale versions"
	@echo "CLI version:"; $(TS_BIN) version || true
	@echo "Daemon version:"; sudo tailscaled --version || true
