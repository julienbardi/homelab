# mk/90_help.mk
# ------------------------------------------------------------
# Help system (pure, dependency‑free)
# ------------------------------------------------------------

DOCS_DIR ?= $(DOCS_DIR)

# ------------------------------------------------------------
# Public entrypoint
# ------------------------------------------------------------
help: help-docs-install
	@if [ "$(VERBOSE)" -ne 0 ]; then \
		echo "ℹ️  Pretty Markdown rendering is optional."; \
		echo "ℹ️  If you install 'mdr', 'glow', or 'mdcat' manually, help will render nicely."; \
		echo "ℹ️  Otherwise, raw Markdown will be shown."; \
	fi
	# Pretty renderer if available, raw fallback otherwise
	@if command -v mdr >/dev/null 2>&1; then \
		mdr $(DOCS_DIR)/help.md; \
	elif command -v glow >/dev/null 2>&1; then \
		glow $(DOCS_DIR)/help.md; \
	elif command -v mdcat >/dev/null 2>&1; then \
		mdcat $(DOCS_DIR)/help.md; \
	else \
		cat $(DOCS_DIR)/help.md; \
	fi

# ------------------------------------------------------------
# Preconditions
# ------------------------------------------------------------
.PHONY: prereqs-docs-verify
prereqs-docs-verify:
	@echo "ℹ️  Pretty Markdown rendering is optional."
	@echo "ℹ️  If you install 'mdr', 'glow', or 'mdcat' manually, help will render nicely."
	@echo "ℹ️  Otherwise, raw Markdown will be shown."

# ------------------------------------------------------------
# Idempotent help doc install (IFC v2)
# ------------------------------------------------------------
.PHONY: help-docs-install
help-docs-install: ensure-run-as-root
	@$(run_as_root) install -d -o root -g root -m 0755 $(DOCS_DIR)
	@{ \
		$(INSTALL_FILE_IF_CHANGED) -q \
			"" "" "$(MAKEFILE_DIR)docs/help.md" \
			"" "" "$(DOCS_DIR)/help.md" \
			"root" "root" "0644"; \
		rc=$$?; \
		[ $$rc -eq 0 ] || [ $$rc -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; \
	}
