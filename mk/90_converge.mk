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

.PHONY: converge-network

converge-network:
	@if [ "$(FORCE)" != "1" ]; then \
		echo "ERROR: converge-network requires FORCE=1"; \
		echo "       (rewrites WireGuard state)"; \
		exit 1; \
	fi
	@echo "🚀 Converging full WireGuard + firewall state"

	$(run_as_root) $(MAKE) all-wg CONF_FORCE=1

	@echo "🔁 Regenerating client configs (parallel)"
	$(run_as_root) /bin/sh -eu -c '\
		set -o pipefail; \
		for i in 0 1 2 3 4 5 6 7; do \
			FORCE_REASSIGN=1 FORCE=1 CONF_FORCE=1 $(MAKE) regen-clients IFACE=wg$$i & \
		done; \
		wait'

	$(run_as_root) $(MAKE) all-wg-up
	$(run_as_root) $(MAKE) wg-add-peers
	$(run_as_root) scripts/setup-subnet-router.nft.sh

	@echo "✅ Network convergence complete"
