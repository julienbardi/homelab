
# ============================================================
# mk/lint.mk — lint orchestration
# ============================================================

# ShellCheck configuration (use repo root as source path so no hardcoded directives)
# Use repo root as source path even when make is run with -C mk
REPO_ROOT := $(abspath $(CURDIR)/..)
SHELLCHECK ?= shellcheck
SHELLCHECK_OPTS ?= -x --external-sources --source-path=$(REPO_ROOT)

# --- Lint target ---
.PHONY: lint lint-scripts lint-config lint-makefile lint-headscale lint-shellcheck

lint: lint-scripts lint-config lint-makefile lint-headscale

# Run shell syntax check and ShellCheck
lint-scripts:
	@echo "Checking shell syntax..."
	@bash -n scripts/setup/*.sh scripts/helpers/*.sh scripts/audit/*.sh scripts/deploy/*.sh
	@echo "Running ShellCheck..."
	@$(MAKE) lint-shellcheck

# Run ShellCheck with external sources enabled and repo as source path
lint-shellcheck:
	@echo "ShellCheck: scripts/setup/*.sh"
	@$(SHELLCHECK) $(SHELLCHECK_OPTS) scripts/setup/*.sh || true
	@echo "ShellCheck: scripts/helpers/*.sh"
	@$(SHELLCHECK) $(SHELLCHECK_OPTS) scripts/helpers/*.sh || true
	@echo "ShellCheck: scripts/audit/*.sh"
	@$(SHELLCHECK) $(SHELLCHECK_OPTS) scripts/audit/*.sh || true
	@echo "ShellCheck: scripts/deploy/*.sh"
	@$(SHELLCHECK) $(SHELLCHECK_OPTS) scripts/deploy/*.sh || true

lint-config:
	@$(run_as_root) headscale configtest --config /etc/headscale/headscale.yaml || \
		(echo "Headscale config invalid!" && exit 1)

lint-makefile:
	@if command -v checkmake >/dev/null 2>&1; then \
		$(run_as_roots) checkmake Makefile; \
		$(run_as_roots) checkmake --version; \
	else \
		make -n all >/dev/null; \
	fi

# Run headscale configtest against the deployed config
lint-headscale:
	@echo "Linting /etc/headscale/headscale.yaml..."
	@sudo headscale configtest --config /etc/headscale/headscale.yaml
