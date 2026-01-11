# ============================================================
# mk/90_converge.mk — Explicit full network convergence
#
# This target intentionally rewrites WireGuard state:
# - regenerates server configs
# - reassigns client IPs if needed
# - brings up all interfaces
# - reconciles kernel peer state
# - reapplies nftables policy
#
# Intentionally state-rewriting. Requires FORCE=1.
# sudo FORCE=1 make converge-network
# Keeps bin/run-as-root unchanged (argv tokens contract).
# ============================================================

.PHONY: converge-network regen-clients-all

converge-network:
	@if [ "$(FORCE)" != "1" ]; then \
		echo "ERROR: converge-network requires FORCE=1"; \
		echo "       (rewrites WireGuard state)"; \
		exit 1; \
	fi
	@echo "🚀 Converging full WireGuard + firewall state"

	$(MAKE) -f $(MAKEFILE_CANONICAL) all-wg CONF_FORCE=1

	@echo "🔁 Regenerating client configs (parallel)"
	$(MAKE) -f $(MAKEFILE_CANONICAL) regen-clients-all FORCE_REASSIGN=1 FORCE=1 CONF_FORCE=1

	$(MAKE) -f $(MAKEFILE_CANONICAL) all-wg-up
	$(MAKE) -f $(MAKEFILE_CANONICAL) wg-add-peers
	$(run_as_root) scripts/setup-subnet-router.nft.sh

	@echo "✅ Network convergence complete"

# ------------------------------------------------------------
# Parallel client regeneration (Make-level fan-out)
# ------------------------------------------------------------

ifneq ($(filter command line environment,$(origin WG_ROOT)),)
WG_IFACES = $(shell $(SCRIPTS)/wg-plan-ifaces.sh "$(WG_ROOT)/compiled/plan.tsv")
endif

regen-clients-all: $(WG_IFACES:%=regen-client-%)

.PHONY: $(WG_IFACES:%=regen-client-%)

regen-client-%:
	$(MAKE) -f $(MAKEFILE_CANONICAL) regen-clients IFACE=$*
