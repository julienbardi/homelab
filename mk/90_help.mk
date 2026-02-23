# mk/90_help.mk
DOCS_DIR := $(DOCS_DIR)

.PHONY: help
help:
	@test -r $(DOCS_DIR)/help.md || { \
		echo "❌ Help is not installed at $(DOCS_DIR)/help.md"; \
		echo "👉 Run: make install-docs"; \
		exit 1; \
	}
	@command -v glow >/dev/null && glow $(DOCS_DIR)/help.md || cat $(DOCS_DIR)/help.md

.PHONY: install-docs
install-docs: ensure-run-as-root
	@$(run_as_root) install -d -o root -g root -m 0755 $(DOCS_DIR)
	@$(run_as_root) install -o root -g root -m 0644 $(MAKEFILE_DIR)docs/help.md $(DOCS_DIR)/help.md