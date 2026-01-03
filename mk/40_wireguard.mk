# ============================================================
# mk/40_wireguard.mk — Essential WireGuard workflow
# - Authoritative CSV → validated compile → atomic deploy
# - No FORCE flags; failures leave last-known-good intact
# ============================================================

WG_ROOT := /volume1/homelab/wireguard
WG_INPUT := $(WG_ROOT)/input
WG_CSV   := $(WG_INPUT)/clients.csv

SCRIPTS := $(CURDIR)/scripts

WG_COMPILE_SCRIPT := $(SCRIPTS)/wg-compile.sh
WG_EXPORT_SCRIPT  := $(SCRIPTS)/wg-client-export.sh
WG_DEPLOY_SCRIPT  := $(SCRIPTS)/wg-deploy.sh
WG_CHECK_SCRIPT   := $(SCRIPTS)/wg-check.sh

# Discover interfaces from CSV (single source of truth)
WG_IFACES := $(shell awk -F, 'NR>1 && $$3 != "iface" {gsub(/^[[:space:]]+|[[:space:]]+$$/, "", $$3); if ($$3!="") print $$3}' $(WG_CSV) | sort -u)

.PHONY: wg-validate wg-apply wg-compile wg-deploy wg-status wg-client-export wg-check

# ------------------------------------------------------------
# Compile intent → artifacts (no deployment)
# ------------------------------------------------------------
wg-compile: $(WG_CSV) $(WG_COMPILE_SCRIPT)
	@echo "▶ compiling WireGuard intent"
	@$(WG_COMPILE_SCRIPT)

# ------------------------------------------------------------
# Deploy compiled state (requires successful compile)
# ------------------------------------------------------------
wg-deploy: $(WG_DEPLOY_SCRIPT)
	@echo "▶ deploying WireGuard state"
	@$(run_as_root) $(WG_DEPLOY_SCRIPT)

# ------------------------------------------------------------
# Full workflow: compile → deploy
# ------------------------------------------------------------
wg-apply: wg-compile wg-deploy wg-client-export

	@echo "✅ WireGuard converged successfully"

# ------------------------------------------------------------
# Validate only (alias)
# ------------------------------------------------------------
wg-validate: wg-compile
	@echo "✅ validation OK"

# ------------------------------------------------------------
# Client config export (depends on compiled state)
# ------------------------------------------------------------
wg-client-export: $(WG_CSV) $(WG_EXPORT_SCRIPT)
	@echo "▶ exporting WireGuard client configs"
	@$(WG_EXPORT_SCRIPT)

# ------------------------------------------------------------
# Consistency / sanity checks
# ------------------------------------------------------------
wg-check: $(WG_CHECK_SCRIPT)
	@echo "▶ validating WireGuard intent"
	@$(run_as_root) $(WG_CHECK_SCRIPT)

.PHONY: wg-rebuild-all
wg-rebuild-all:
	@echo "⚠️  FULL WireGuard rebuild (keys + config)"
	@echo "⚠️  This will invalidate ALL existing clients"
	@echo "⚠️  Press Ctrl-C now if this is not intended"
	@sleep 5
	@echo "▶ recording compromised WireGuard keys"
	@$(run_as_root) $(SCRIPTS)/wg-record-compromised-keys.sh
	@echo "▶ destroying existing WireGuard state"
	@$(run_as_root) $(SCRIPTS)/wg-nuke.sh
	@$(MAKE) wg-apply
	@echo "🔥 WireGuard fully rebuilt with fresh keys"

