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

    $(run_as_root) /bin/sh -eu -c 'FORCE_REASSIGN=1 FORCE=1 CONF_FORCE=1 $(MAKE) regen-clients IFACE=wg0'
    $(run_as_root) /bin/sh -eu -c 'FORCE_REASSIGN=1 FORCE=1 CONF_FORCE=1 $(MAKE) regen-clients IFACE=wg1'
    $(run_as_root) /bin/sh -eu -c 'FORCE_REASSIGN=1 FORCE=1 CONF_FORCE=1 $(MAKE) regen-clients IFACE=wg2'
    $(run_as_root) /bin/sh -eu -c 'FORCE_REASSIGN=1 FORCE=1 CONF_FORCE=1 $(MAKE) regen-clients IFACE=wg3'
    $(run_as_root) /bin/sh -eu -c 'FORCE_REASSIGN=1 FORCE=1 CONF_FORCE=1 $(MAKE) regen-clients IFACE=wg4'
    $(run_as_root) /bin/sh -eu -c 'FORCE_REASSIGN=1 FORCE=1 CONF_FORCE=1 $(MAKE) regen-clients IFACE=wg5'
    $(run_as_root) /bin/sh -eu -c 'FORCE_REASSIGN=1 FORCE=1 CONF_FORCE=1 $(MAKE) regen-clients IFACE=wg6'
    $(run_as_root) /bin/sh -eu -c 'FORCE_REASSIGN=1 FORCE=1 CONF_FORCE=1 $(MAKE) regen-clients IFACE=wg7'

    $(run_as_root) $(MAKE) all-wg-up
    $(run_as_root) $(MAKE) wg-add-peers
    $(run_as_root) scripts/setup-subnet-router.nft.sh

    @echo "✅ Network convergence complete"
