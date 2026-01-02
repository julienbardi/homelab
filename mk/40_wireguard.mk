# ============================================================
# mk/40_wireguard.mk — Essential WireGuard workflow
# - Authoritative CSV → validated compile → atomic deploy
# - No FORCE flags; failures leave last-known-good intact
# ============================================================

WG_ROOT := /volume1/homelab/wireguard
SCRIPTS := $(CURDIR)/scripts

.PHONY: wg-validate wg-apply wg-compile wg-deploy wg-status

# Validate + compile only (no deployment)
wg-compile:
	@echo "▶ compiling WireGuard intent"
	@$(SCRIPTS)/wg-compile.sh

# Deploy compiled state (requires successful compile)
wg-deploy:
	@echo "▶ deploying WireGuard state"
	@$(SCRIPTS)/wg-deploy.sh

# Full workflow: compile → deploy
wg-apply: wg-compile wg-deploy
	@echo "✅ WireGuard converged successfully"

# Validate only (alias)
wg-validate: wg-compile
	@echo "✅ validation OK"

# Quick status helper (delegates to existing status tooling)
wg-status:
	@$(MAKE) -s -f mk/41_wireguard-status.mk wg-status
