# mk/90_help.mk
# ------------------------------------------------------------
# Help system (pure, dependency‑free)
# ------------------------------------------------------------

# Public entrypoint (no forced escalation)
.PHONY: help
help: help-docs-install help-render

# Opportunistic doc install (conditional escalation)
.PHONY: help-docs-install
help-docs-install: install-all
	$(ENSURE_DIR) root admin 0775 $(DOCS_DIR);
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

.PHONY: bootstrap-acl
bootstrap-acl:
	@echo "🔧 Ensuring Ugreen‑safe ACLs for docs directory"
	sudo chown root:admin $(DOCS_DIR)
	sudo chmod 0775 $(DOCS_DIR)

UGREEN_ACL_DIRS := $(HOMELAB_ROOT)/docs

.PHONY: audit-acl
audit-acl:
	@echo "🔍 Auditing Ugreen‑ACL directories"
	@for d in $(UGREEN_ACL_DIRS); do \
		if [ ! -d $$d ]; then echo "❌ Missing: $$d"; continue; fi; \
		owner=$$(stat -c "%U" $$d); \
		group=$$(stat -c "%G" $$d); \
		mode=$$(stat -c "%a" $$d); \
		if [ "$$owner" = "root" ] && [ "$$group" = "admin" ] && [ "$$mode" = "775" ]; then \
			echo "✔️ $$d root:admin 775"; \
		else \
			echo "❌ $$d $$owner:$$group $$mode"; \
		fi; \
	done

