# ============================================================
# mk/40_wireguard.mk — Essential WireGuard workflow
# - Authoritative CSV → validated compile → atomic deploy
# - No FORCE flags; failures leave last-known-good intact
# ============================================================

WG_ROOT := /volume1/homelab/wireguard
export WG_ROOT

WG_INPUT := $(WG_ROOT)/input
WG_CSV   := $(WG_INPUT)/clients.csv

SCRIPTS := $(CURDIR)/scripts

WG_COMPILE_SCRIPT := $(SCRIPTS)/wg-compile.sh
WG_KEYS_SCRIPT    := $(SCRIPTS)/wg-compile-keys.sh
WG_SERVER_KEYS_SCRIPT := $(SCRIPTS)/wg-ensure-server-keys.sh
WG_RENDER_SCRIPT  := $(SCRIPTS)/wg-compile-clients.sh
WG_EXPORT_SCRIPT  := $(SCRIPTS)/wg-client-export.sh
WG_DEPLOY_SCRIPT  := $(SCRIPTS)/wg-deploy.sh
WG_CHECK_SCRIPT   := $(SCRIPTS)/wg-check.sh
WG_SERVER_BASE_RENDER_SCRIPT := $(SCRIPTS)/wg-render-server-base.sh
WG_RENDER_CHECK_SCRIPT := $(SCRIPTS)/wg-check-render.sh

.PHONY: wg-validate wg-apply wg-render-server-base wg-compile wg-deployed wg-status wg-check \
	wg-rebuild-clean wg-rebuild-all wg-check-render

# ------------------------------------------------------------
# Compile intent → plan.tsv
# ------------------------------------------------------------
wg-compile-intent: $(WG_CSV) $(WG_COMPILE_SCRIPT)
	@test -x "$(WG_COMPILE_SCRIPT)"
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_COMPILE_SCRIPT)"


wg-ensure-server-keys: wg-compile-intent $(WG_SERVER_KEYS_SCRIPT)
	@test -x "$(WG_SERVER_KEYS_SCRIPT)"
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_SERVER_KEYS_SCRIPT)"

# ------------------------------------------------------------
# Generate client keys → keys.tsv
# ------------------------------------------------------------
wg-compile-keys: wg-compile-intent $(WG_KEYS_SCRIPT)
	@test -x "$(WG_KEYS_SCRIPT)"
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_KEYS_SCRIPT)"

# ------------------------------------------------------------
# Render client + server configs from plan.tsv + keys.tsv
# ------------------------------------------------------------
wg-render-server-base: wg-compile-intent
	@test -x "$(WG_SERVER_BASE_RENDER_SCRIPT)"
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_SERVER_BASE_RENDER_SCRIPT)"


wg-render: wg-compile-intent wg-compile-keys wg-ensure-server-keys wg-render-server-base
	@test -x "$(WG_RENDER_SCRIPT)"
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_RENDER_SCRIPT)"

# ------------------------------------------------------------
# Compile everything (no deployment)
# ------------------------------------------------------------
wg-compile: wg-compile-intent wg-compile-keys wg-render wg-check-render wg-check

# ------------------------------------------------------------
# Deploy compiled state (requires successful compile)
# ------------------------------------------------------------
wg-deployed: ensure-run-as-root net-tunnel-preflight wg-compile wg-check
	@test -x "$(WG_DEPLOY_SCRIPT)"
	@echo "🔄 WireGuard deployment requested"
	@$(run_as_root) $(WG_DEPLOY_SCRIPT)

wg-apply: wg-deployed
	@test -x "$(WG_EXPORT_SCRIPT)"
	@$(run_as_root) $(WG_EXPORT_SCRIPT)
	@echo "✅ WireGuard converged"

# ------------------------------------------------------------
# Consistency / sanity checks
# ------------------------------------------------------------
wg-check: ensure-run-as-root
	@test -x "$(WG_CHECK_SCRIPT)"
	@$(run_as_root) $(WG_CHECK_SCRIPT)

wg-rebuild-clean: ensure-run-as-root
	@echo "🔥 FULL WireGuard rebuild (keys + config)"
	@echo "⚠️  This will invalidate ALL existing clients"
	@echo "⚠️  Press Ctrl-C now if this is not intended"
	@sleep 5
	@echo "▶ recording compromised WireGuard keys"
	@$(run_as_root) $(SCRIPTS)/wg-record-compromised-keys.sh
	@echo "▶ destroying existing WireGuard state"
	@$(run_as_root) $(SCRIPTS)/wg-nuke.sh

wg-rebuild-all: wg-rebuild-clean wg-apply
	@echo "🔥 WireGuard fully rebuilt with fresh keys"

wg-check-render: wg-render
	@test -x "$(WG_RENDER_CHECK_SCRIPT)"
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_RENDER_CHECK_SCRIPT)"
