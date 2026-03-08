# ------------------------------------------------------------
# Help system (pure, dependency‑free)
# ------------------------------------------------------------

DOCS_DIR ?= $(DOCS_DIR)

.PHONY: help
help: prereqs-docs-verify
	@test -r $(DOCS_DIR)/help.md || { \
		echo "❌ Help is not installed at $(DOCS_DIR)/help.md"; \
		echo "👉 Run: make install-docs"; \
		exit 1; \
	}
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

.PHONY: prereqs-docs-verify
prereqs-docs-verify:
	@echo "ℹ️  Pretty Markdown rendering is optional."
	@echo "ℹ️  If you install 'mdr', 'glow', or 'mdcat' manually, help will render nicely."
	@echo "ℹ️  Otherwise, raw Markdown will be shown."

# ------------------------------------------------------------
# Install docs
# ------------------------------------------------------------
.PHONY: install-docs
install-docs: ensure-run-as-root
	@$(run_as_root) install -d -o root -g root -m 0755 $(DOCS_DIR)
	@$(run_as_root) install -o root -g root -m 0644 $(MAKEFILE_DIR)docs/help.md $(DOCS_DIR)/help.md
	@echo "📄 Help docs installed to $(DOCS_DIR)"
