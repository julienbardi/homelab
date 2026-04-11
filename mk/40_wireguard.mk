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

# ------------------------------------------------------------
# WIREGUARD CONTROL PLANE
# ------------------------------------------------------------

.PHONY: wg-generate
wg-generate:
	@./scripts/wg-generate-configs.sh

# ------------------------------------------------------------
# INSTALLATION
# ------------------------------------------------------------

.PHONY: wg-install-router
wg-install-router:
	@./scripts/wg-install-router.sh

.PHONY: wg-install-nas
wg-install-nas:
	@./scripts/wg-install-nas.sh

# ------------------------------------------------------------
# BRING-UP / TEARDOWN
# ------------------------------------------------------------

.PHONY: wg-up-router
wg-up-router:
	@./scripts/wg-up-router.sh

.PHONY: wg-up-nas
wg-up-nas:
	@./scripts/wg-up-nas.sh

.PHONY: wg-down-router
wg-down-router:
	@./scripts/wg-down-router.sh

.PHONY: wg-down-nas
wg-down-nas:
	@./scripts/wg-down-nas.sh

# ------------------------------------------------------------
# STATUS
# ------------------------------------------------------------

.PHONY: wg-status
wg-status:
	@./scripts/wg-status-router.sh || true
	@./scripts/wg-status-nas.sh || true

# ------------------------------------------------------------
# FULL CONVERGENCE
# ------------------------------------------------------------

.PHONY: wg-up
wg-up: wg-generate wg-install-router wg-install-nas wg-up-router wg-up-nas
	@echo "🚀 WireGuard fully converged"

.PHONY: wg-down
wg-down: wg-down-router wg-down-nas
	@echo "🛑 WireGuard fully stopped"
