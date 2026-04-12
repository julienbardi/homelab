# mk/90_help.mk
# ------------------------------------------------------------
# Help system (pure, dependency‑free)
# ------------------------------------------------------------

# Public entrypoint (no forced escalation)
.PHONY: help
help: help-docs-install help-render

# Opportunistic doc install (conditional escalation)
.PHONY: help-docs-install
help-docs-install:
	@$(ENSURE_DIR) root root 0755 $(DOCS_DIR)
	@env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
	$(INSTALL_FILE_IF_CHANGED) -q \
		"" "" "$(REPO_ROOT)docs/help.md" \
		"" "" "$(DOCS_DIR)/help.md" \
		"root" "root" "0644" \
		|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]

# Help rendering (always unprivileged)
.PHONY: help-render
help-render:
	@if [ "$(VERBOSE)" -ne 0 ]; then \
		echo "ℹ️  Pretty Markdown rendering is optional."; \
		echo "ℹ️  Install 'mdr', 'glow', or 'mdcat' for nicer output."; \
	fi
	@if command -v mdr >/dev/null 2>&1; then \
		mdr $(DOCS_DIR)/help.md; \
	elif command -v glow >/dev/null 2>&1; then \
		glow $(DOCS_DIR)/help.md; \
	elif command -v mdcat >/dev/null 2>&1; then \
		mdcat $(DOCS_DIR)/help.md; \
	else \
		cat $(DOCS_DIR)/help.md; \
	fi
