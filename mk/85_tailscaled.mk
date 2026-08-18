# --------------------------------------------------------------------
# mk/85_tailscaled.mk — tailscaled client management
# --------------------------------------------------------------------
# CONTRACT:
# - Provides service-specific recipes for tailscaled:
#   * LAN role: stable node, advertises LAN + exit-node
#   * WAN role: ephemeral roaming node, internet-only
# - All enrollment happens against Headscale (custom control plane).
# - NAS acts as authoritative exit-node + LAN router for the tailnet.
# - DNS must remain under homelab control (no Tailscale DNS hijack).
# - Routes must remain deterministic (NAS advertises, others do not).
# --------------------------------------------------------------------

TAILSCALE_KEYRING := /usr/share/keyrings/tailscale-archive-keyring.gpg
TAILSCALE_KEY_URL := https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg

TAILSCALE_REPO_FILE := /etc/apt/sources.list.d/tailscale.list
TAILSCALE_REPO_LINE := deb [signed-by=$(TAILSCALE_KEYRING)] https://pkgs.tailscale.com/stable/debian bookworm main

TS_BIN ?= /usr/bin/tailscale
HS_BIN ?= /usr/local/bin/headscale

# Headscale user lookup:
# Each device must authenticate using a Headscale preauth key.
# LAN user = stable identity; WAN user = ephemeral identity.
define headscale_user_id
$(shell [ -x "$(HS_BIN)" ] && command -v jq >/dev/null 2>&1 && \
	$(run_as_root) "$(HS_BIN)" users list --output json \
	| jq -r '.[]? // empty | select(.name=="$(1)") | .id')
endef
#	| jq -r '.[] | select(.name=="$(1)") | .id' || true)


HS_USER_LAN := $(call headscale_user_id,lan)
HS_USER_WAN := $(call headscale_user_id,wan)

SYSTEMD_SRC_DIR := $(REPO_ROOT)/config/systemd

.PHONY: tailscaled-check-deps \
	tailscaled-lan tailscaled-wan \
	enable-tailscaled start-tailscaled stop-tailscaled \
	tailscaled-status tailscaled-logs tailscale-check

# --------------------------------------------------------------------
# Verify dependencies (fail fast)
# tailscaled must exist, headscale must exist, jq must exist.
# --------------------------------------------------------------------
tailscaled-check-deps:
	@for c in jq xargs $(TS_BIN) $(HS_BIN); do \
		command -v $$c >/dev/null 2>&1 || { echo "❌ $$c not found"; exit 1; }; \
	done

.NOTPARALLEL: tailscaled-lan tailscaled-wan

# --------------------------------------------------------------------
# LAN client (trusted: LAN + exit-node)
# --------------------------------------------------------------------
# NAS is the authoritative exit-node and LAN router for the tailnet.
# - Advertises LAN routes (IPv4 + IPv6)
# - Advertises exit-node (IPv4 + IPv6)
# - Accepts routes from Headscale (safe because NAS is the only advertiser)
# - Rejects DNS hijack (homelab DNS must remain authoritative)
# - Never uses another exit-node (--exit-node=false)
# --------------------------------------------------------------------
tailscaled-lan: tailscaled-check-deps net-tunnel-preflight firewall-nas
	@if [ "$(USE_TAILSCALED)" != "1" ]; then \
		echo "ℹ️ tailscaled-lan: USE_TAILSCALED=$(USE_TAILSCALED); skipping LAN enrollment"; \
		exit 0; \
	fi; \
	echo "🔑 Enrolling LAN client (bardi-lan / lan)"; \
	AUTH_KEY=$$($(run_as_root) $(HS_BIN) preauthkeys create \
		--user $(HS_USER_LAN) \
		--output json | jq -r '.key'); \
	$(run_as_root) $(TS_BIN) up --reset \
		--login-server=https://vpn.bardi.ch \
		--authkey="$$AUTH_KEY" \
		--advertise-exit-node \
		--advertise-exit-node-ipv6 \
		--advertise-routes=10.89.12.0/24,fd89:7a3b:42c0::/64 \
		--accept-dns=false \
		--accept-routes=true \
		--exit-node=false; \
	echo "📊 LAN exit-node + subnet route advertised"; \
	$(run_as_root) $(TS_BIN) status --json | jq '.Self.CapMap'; \
	echo "✅ LAN client configured"

# --------------------------------------------------------------------
# WAN client (internet-only)
# --------------------------------------------------------------------
# WAN role is for roaming devices:
# - Ephemeral key (non-reusable, safe for mobile/laptop)
# - No LAN advertisement
# - No route acceptance
# - No exit-node advertisement
# - No DNS hijack
# --------------------------------------------------------------------
tailscaled-wan: tailscaled-check-deps
	@if [ "$(USE_TAILSCALED)" != "1" ]; then \
		echo "ℹ️ tailscaled-wan: USE_TAILSCALED=$(USE_TAILSCALED); skipping WAN enrollment"; \
		exit 0; \
	fi; \
	echo "🔑 Enrolling WAN client (bardi-wan / wan)"; \
	AUTH_KEY=$$($(run_as_root) $(HS_BIN) preauthkeys create \
		--user $(HS_USER_WAN) \
		--ephemeral=true \
		--output json | jq -r '.key'); \
	$(run_as_root) $(TS_BIN) up --reset \
		--login-server=https://vpn.bardi.ch \
		--authkey="$$AUTH_KEY" \
		--accept-dns=false \
		--exit-node=false \
		--accept-routes=false; \
	echo "✅ WAN client configured (internet-only)"

# --------------------------------------------------------------------
# Install and enable services at boot
# tailscaled-lan.service ensures NAS stays enrolled + advertises routes.
# --------------------------------------------------------------------
enable-tailscaled:
	@if [ "$(USE_TAILSCALED)" != "1" ]; then \
        echo "ℹ️ enable-tailscaled: USE_TAILSCALED=$(USE_TAILSCALED); skipping"; \
        exit 0; \
    fi; \
	echo "🔧 Installing systemd role units"; \
	$(run_as_root) install -o $(ROOT_UID) -g $(ROOT_GID) -m 644 \
		$(SYSTEMD_SRC_DIR)/tailscaled-lan.service \
		$(SYSTEMD_DIR)/tailscaled-lan.service
	@$(systemctl_daemon_reload)
	@$(run_as_root) systemctl enable tailscaled tailscaled-lan.service
	@echo "🚀 Enabled at boot: tailscaled + role service"

# --------------------------------------------------------------------
# Runtime control
# --------------------------------------------------------------------
start-tailscaled:
	@if [ "$(USE_TAILSCALED)" != "1" ]; then \
		echo "ℹ️ start-tailscaled: USE_TAILSCALED=$(USE_TAILSCALED); skipping"; \
		exit 0; \
	fi; \
	$(run_as_root) systemctl start tailscaled tailscaled-lan.service; \
	echo "🚀 Started: tailscaled + role service"

stop-tailscaled:
	@if [ "$(USE_TAILSCALED)" != "1" ]; then \
		echo "ℹ️ stop-tailscaled: USE_TAILSCALED=$(USE_TAILSCALED); skipping"; \
		exit 0; \
	fi; \
	$(run_as_root) systemctl stop tailscaled tailscaled-lan.service; \
	echo "⚙️ Stopped: tailscaled + role service"

# --------------------------------------------------------------------
# Status and logs
# --------------------------------------------------------------------
tailscaled-status: install-pkg-vnstat
	@if [ "$(USE_TAILSCALED)" != "1" ]; then \
		echo "ℹ️ tailscaled-status: USE_TAILSCALED=$(USE_TAILSCALED); skipping status check"; \
		exit 0; \
	fi; \
	echo "🔍 tailscaled health + stats"; \
	echo "📦 daemon:"; $(run_as_root) systemctl is-active tailscaled || echo "❌ inactive"; \
	echo "🔧 role unit:"; $(run_as_root) systemctl is-enabled tailscaled-lan.service || echo "❌ not enabled"; \
	echo "📊 connected nodes:"; $(run_as_root) $(TS_BIN) status | awk '{print $$1, $$2, $$3}'; \
	echo "📊 monthly traffic:"; vnstat -i tailscale0 -m || true; \
	echo "⚙️ connection events (1h):"; \
		$(run_as_root) journalctl -u tailscaled --since "1 hour ago" \
		| grep -i connection | wc -l | xargs echo "events"; \
	echo "📋 versions:"; \
	echo "    CLI:"; $(TS_BIN) version || true; \
	echo "    Daemon:"; $(run_as_root) tailscaled --version || true

tailscaled-logs:
	@if [ "$(USE_TAILSCALED)" != "1" ]; then \
		echo "ℹ️ tailscaled-logs: USE_TAILSCALED=$(USE_TAILSCALED); skipping"; \
		exit 0; \
	fi; \
	echo "📜 Tailing logs (Ctrl-C to exit)"; \
	$(run_as_root) journalctl -u tailscaled -u tailscaled-lan.service -f


tailscale-check:
	@if [ "$(USE_TAILSCALED)" != "1" ]; then \
		echo "ℹ️ tailscale-check: USE_TAILSCALED=$(USE_TAILSCALED); skipping"; \
		exit 0; \
	fi; \
	echo "🔍 Checking Tailscale versions"; \
	echo "CLI:"; $(TS_BIN) version || true; \
	echo "Daemon:"; $(run_as_root) tailscaled --version || true


# tailscaled is required for:
# - NAS exit-node advertisement (IPv4 + IPv6)
# - NAS LAN route advertisement (IPv4 + IPv6)
# - Headscale enrollment
# - fallback remote access
# - deterministic routing
USE_TAILSCALED ?= 1

# --------------------------------------------------------------------
# tailscaled preflight
# Ensures:
# - tailscaled installed
# - tailscaled running
# - tailscaled listening on control port :41641
# Prevents partial enrollment or route advertisement during degraded state.
# --------------------------------------------------------------------
.PHONY: net-tunnel-preflight
net-tunnel-preflight:
	@if [ "$(USE_TAILSCALED)" != "1" ]; then \
		echo "ℹ️ net-tunnel-preflight: tailscaled disabled (USE_TAILSCALED=$(USE_TAILSCALED)); skipping tailscaled checks"; \
		exit 0; \
	fi; \
	set -euo pipefail; \
	if ! command -v tailscaled >/dev/null 2>&1; then \
		echo "❌ tailscaled not installed — run 'make prereqs'"; \
		exit 1; \
	fi; \
	if ! systemctl is-active --quiet tailscaled; then \
		echo "ℹ️ Starting tailscaled service"; \
		$(run_as_root) systemctl start tailscaled || true; \
	fi; \
	timeout=30; \
	while ! ss -ltnp 2>/dev/null | grep -q ':41641'; do \
		timeout=$$((timeout-1)); \
		if [ $$timeout -le 0 ]; then \
			echo "❌ tailscaled not listening on control port :41641"; exit 1; \
		fi; \
		sleep 1; \
	done; \
	echo "✅ net-tunnel preflight OK (tailscaled enabled)"
