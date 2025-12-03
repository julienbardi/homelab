# --------------------------------------------------------------------
# mk/82_tailscaled.mk — tailscaled client management
# --------------------------------------------------------------------
# CONTRACT:
# - Provides service-specific recipes for tailscaled:
#   * ACL install
#   * ephemeral key onboarding (family/guest)
#   * systemd unit install/enable
#   * status + logs
# - Does NOT define global lifecycle targets (clean, reload, restart).
#   Those are centralized in the root Makefile to cover all services.
# - Recipes must remain operator-safe: no secrets written to disk,
#   ephemeral+non-reusable keys only, safe file ownership/permissions.
# --------------------------------------------------------------------

TS_BIN      ?= /usr/bin/tailscale
HS_BIN      ?= /usr/bin/headscale
HS_USER_FAM := $(shell sudo headscale users list --output json | jq -r '.[] | select(.name=="bardi-family") | .id')
HS_USER_GUE := $(shell sudo headscale users list --output json | jq -r '.[] | select(.name=="bardi-guests") | .id')
ACL_SRC     ?= /home/julie/src/homelab/config/headscale/acl.json
ACL_DST     ?= /etc/headscale/acl.json
SYSTEMD_SRC_DIR ?= /home/julie/src/homelab/config/systemd
SYSTEMD_DST_DIR ?= /etc/systemd/system

.PHONY: check-deps acl-install tailscaled-family tailscaled-guest \
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

# Bring up tailscaled for family (LAN + exit node) using one-time ephemeral key
tailscaled-family: acl-install
	@echo "🔑 Creating ephemeral one-time key for bardi-family (ID: $(HS_USER_FAM))"
	@sudo $(HS_BIN) preauthkeys create --user $(HS_USER_FAM) --ephemeral=true --reusable=false --output json \
	| jq -r '.key' \
	| xargs -I{} sh -c 'echo "➡️ Consuming ephemeral key for family"; sudo $(TS_BIN) up --reset \
		--authkey={} \
		--advertise-exit-node \
		--advertise-routes=10.89.12.0/24 \
		--accept-dns=true \
		--accept-routes=true'
	@echo "✅ Family node configured: exit-node + route 10.89.12.0/24"

# Bring up tailscaled for guest (exit node only) using one-time ephemeral key
tailscaled-guest: acl-install
	@echo "🔑 Creating ephemeral one-time key for bardi-guests (ID: $(HS_USER_GUE))"
	@sudo $(HS_BIN) preauthkeys create --user $(HS_USER_GUE) --ephemeral=true --reusable=false --output json \
	| jq -r '.key' \
	| xargs -I{} sh -c 'echo "➡️ Consuming ephemeral key for guests"; sudo $(TS_BIN) up --reset \
		--authkey={} \
		--advertise-exit-node \
		--accept-dns=true \
		--accept-routes=false'
	@echo "✅ Guest node configured: exit-node only"

# Install and enable all services at boot (daemon + family + guest)
enable-tailscaled: acl-install
	@echo "🧩 Installing systemd role units"
	@sudo install -o root -g root -m 644 $(SYSTEMD_SRC_DIR)/tailscaled-family.service $(SYSTEMD_DST_DIR)/tailscaled-family.service
	@sudo install -o root -g root -m 644 $(SYSTEMD_SRC_DIR)/tailscaled-guest.service $(SYSTEMD_DST_DIR)/tailscaled-guest.service
	@sudo systemctl daemon-reload
	@sudo systemctl enable tailscaled tailscaled-family.service tailscaled-guest.service
	@echo "🚀 Enabled at boot: tailscaled + family + guest services"

# Start all services immediately
start-tailscaled:
	@sudo systemctl start tailscaled tailscaled-family.service tailscaled-guest.service
	@echo "▶️ Started: tailscaled + family + guest services"

# Status target: health + operational stats
tailscaled-status: install-pkg-vnstat
	@echo "🔎 tailscaled health + stats"
	@echo "🟢 tailscaled daemon:"; sudo systemctl is-active tailscaled || echo "❌ inactive"
	@echo "👨‍👩‍👧 family service:"; sudo systemctl is-enabled tailscaled-family.service || echo "❌ not enabled"
	@echo "🧑‍🤝‍🧑 guest service:"; sudo systemctl is-enabled tailscaled-guest.service || echo "❌ not enabled"
	@echo "📡 Connected nodes:"; sudo $(TS_BIN) status | awk '{print $$1, $$2, $$3}'
	@echo "📊 Monthly traffic on tailscale0:"; vnstat -i tailscale0 -m || echo "vnstat not installed or no data yet"
	@echo "⚡ Connection events (last hour):"; sudo journalctl -u tailscaled --since "1 hour ago" | grep -i "connection" | wc -l | xargs echo "events"

# Consolidated logs view
tailscaled-logs:
	@echo "📜 Tailing logs for tailscaled + role services (Ctrl-C to exit)"
	@sudo journalctl -u tailscaled -u tailscaled-family.service -u tailscaled-guest.service -f
