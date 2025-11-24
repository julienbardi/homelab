
# ============================================================
# mk/lint.mk — lint orchestration
# ============================================================

# --- Lint target ---
.PHONY: lint lint-scripts lint-config lint-makefile lint-headscale

lint: lint-scripts lint-config lint-makefile lint-headscale

lint-scripts:
	 @bash -n scripts/setup/*.sh scripts/helpers/*.sh scripts/audit/*.sh scripts/deploy/*.sh

lint-config:
	@$(call run_as_root,headscale configtest --config /etc/headscale/headscale.yaml) || \
		(echo "Headscale config invalid!" && exit 1)

lint-makefile:
	@if command -v checkmake >/dev/null 2>&1; then \
		$(call run_as_root,checkmake Makefile); \
		$(call run_as_root,checkmake --version); \
	else \
		make -n all >/dev/null; \
	fi

# Run headscale configtest against the deployed config
lint-headscale:
	@echo "Linting /etc/headscale/headscale.yaml..."
	@sudo headscale configtest --config /etc/headscale/headscale.yaml
