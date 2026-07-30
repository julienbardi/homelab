# --------------------------------------------------------------------
# mk/90_help.mk
# --------------------------------------------------------------------
# Help system (pure, dependency-free)
# --------------------------------------------------------------------

# Public entrypoint (no forced escalation)
.PHONY: help
help: help-docs-install help-render

# Opportunistic doc install (aligned with 01_common.mk contract)
.PHONY: help-docs-install
help-docs-install: install-all | $(run_as_root)
	@if [ -z "$(DOCS_DIR)" ]; then echo "❌ Error: DOCS_DIR is empty."; exit 1; fi
	@status=0; \
	$(run_as_root) sh -c ' \
		install -d -m 0775 -o "$(ROOT_UID)" -g "$(ROOT_GID)" "$(DOCS_DIR)" && \
		CHANGED_EXIT_CODE="$(INSTALL_IF_CHANGED_EXIT_CHANGED)" "$(INSTALL_FILE_IF_CHANGED)" \
			"" "" "$(REPO_ROOT)/docs/help.md" \
			"" "" "$(DOCS_DIR)/help.md" \
			"$(ROOT_UID)" "$(ROOT_GID)" "0644" \
	' || status=$$?; \
	case "$$status" in ''|*[!0-9]*) status=1 ;; esac; \
	if [ $$status -ne 0 ] && [ $$status -ne $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		echo "❌ Fatal error (exit $$status) installing $(DOCS_DIR)/help.md" >&2; \
		exit $$status; \
	fi

# Help rendering (always unprivileged)
.PHONY: help-render
help-render:
	@if [ "$(VERBOSE)" -ne 0 ]; then \
		echo "ℹ️  Pretty Markdown rendering is optional."; \
		echo "ℹ️  Install 'mdr', 'glow', or 'mdcat' for nicer output."; \
	fi
	@if [ ! -f "$(DOCS_DIR)/help.md" ]; then \
		echo "❌ Help file missing at $(DOCS_DIR)/help.md. Run 'make help-docs-install' first."; \
		exit 1; \
	fi
	@if command -v mdr >/dev/null 2>&1; then \
		mdr "$(DOCS_DIR)/help.md"; \
	elif command -v glow >/dev/null 2>&1; then \
		glow "$(DOCS_DIR)/help.md"; \
	elif command -v mdcat >/dev/null 2>&1; then \
		mdcat "$(DOCS_DIR)/help.md"; \
	else \
		cat "$(DOCS_DIR)/help.md"; \
	fi