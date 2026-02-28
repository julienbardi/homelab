# ============================================================
# WireGuard runtime recovery (diagnostic only)
#
# - Intent-driven (compiled/plan.tsv)
# - Does NOT compile, deploy, or mutate configs
# - Safe to run repeatedly
# ============================================================

.PHONY: wg-runtime-recover

wg-runtime-recover: ensure-run-as-root
	@echo "� ️  Runtime recovery only — does not modify intent or compiled artifacts"
	@$(run_as_root) sh -c '\
	    set -e; \
	    args=""; \
	    [ -n "$$IFACES" ] && args="$$args --ifaces $$IFACES"; \
	    [ -n "$$TRIES" ] && args="$$args --tries $$TRIES"; \
	    [ "$$NO_DOWN" = "1" ] && args="$$args --no-down"; \
	    [ "$$DRY_RUN" = "1" ] && args="$$args --dry-run"; \
	    WG_ROOT="$(WG_ROOT)" "$(SCRIPTS)/wg-runtime-recover.sh" $$args; \
	'
