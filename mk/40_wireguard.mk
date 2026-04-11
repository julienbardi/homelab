# mk/40_wireguard.mk
# ------------------------------------------------------------
# WIREGUARD CONTROL PLANE
# ------------------------------------------------------------
#
# Purpose:
#   Full WireGuard lifecycle:
#     - intent → generation
#     - generation → deployment
#     - deployment → bring-up
#
# Scope:
#   - NAS + router orchestration
#   - No inline business logic
#
# Ownership:
#   - All stateful behavior lives in scripts/ and router/jffs/scripts/
#   - This file is orchestration + DAG only
#
# Contracts:
#   - MUST NOT invoke $(MAKE)
#   - MUST be correct under 'make -j'
#   - MUST NOT rely on timestamps for remote state
#
# ------------------------------------------------------------

WGCTL := ./scripts/wgctl.sh

# ------------------------------------------------------------
# GENERATION
# ------------------------------------------------------------

.PHONY: wg-generate
wg-generate:
	@./scripts/wg-generate-configs.sh

# ------------------------------------------------------------
# INSTALLATION
# ------------------------------------------------------------

.PHONY: wg-install-router
wg-install-router:
	@ROUTER_CONTROL_PLANE=1 $(WGCTL) router install

.PHONY: wg-install-nas
wg-install-nas:
	@NAS_CONTROL_PLANE=1 $(WGCTL) nas install

# ------------------------------------------------------------
# BRING-UP / TEARDOWN
# ------------------------------------------------------------

.PHONY: wg-up-router
wg-up-router:
	@ROUTER_CONTROL_PLANE=1 $(WGCTL) router up

.PHONY: wg-up-nas
wg-up-nas:
	@NAS_CONTROL_PLANE=1 $(WGCTL) nas up

.PHONY: wg-down-router
wg-down-router:
	@ROUTER_CONTROL_PLANE=1 $(WGCTL) router down

.PHONY: wg-down-nas
wg-down-nas:
	@NAS_CONTROL_PLANE=1 $(WGCTL) nas down

# ------------------------------------------------------------
# STATUS
# ------------------------------------------------------------

.PHONY: wg-status
wg-status:
	@ROUTER_CONTROL_PLANE=1 $(WGCTL) router status || true
	@NAS_CONTROL_PLANE=1 $(WGCTL) nas status || true

# ------------------------------------------------------------
# FULL CONVERGENCE
# ------------------------------------------------------------

.PHONY: wg-up
wg-up: wg-generate wg-install-router wg-install-nas wg-up-router wg-up-nas
	@echo "🚀 WireGuard fully converged"

.PHONY: wg-down
wg-down: wg-down-router wg-down-nas
	@echo "🛑 WireGuard fully stopped"
