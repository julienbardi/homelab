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
help-docs-install: install-all
	@if [ -z "$(DOCS_DIR)" ]; then echo "❌ Error: DOCS_DIR is empty."; exit 1; fi
	@$(run_as_root) mkdir -p "$(DOCS_DIR)"
	# We use admin here because it's the Ugreen privileged group
	@$(run_as_root) chown $(ROOT_UID):admin "$(DOCS_DIR)"
	@$(run_as_root) chmod 0775 "$(DOCS_DIR)"
	@$(call install_file,$(REPO_ROOT)docs/help.md,$(DOCS_DIR)/help.md,$(ROOT_UID),$(ROOT_GID),0644)

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

.PHONY: bootstrap-acl
bootstrap-acl:
	@echo "🔧 Ensuring Ugreen-safe ACLs for docs directory"
	@$(run_as_root) chown $(ROOT_UID):admin "$(DOCS_DIR)"
	@$(run_as_root) chmod 0775 "$(DOCS_DIR)"

UGREEN_ACL_DIRS := $(DOCS_DIR)

.PHONY: audit-acl
audit-acl:
	@echo "🔍 Auditing Ugreen-ACL directories"
	@for d in $(UGREEN_ACL_DIRS); do \
		if [ ! -d "$$d" ]; then echo "❌ Missing: $$d"; continue; fi; \
		owner=$$(stat -c "%U" "$$d"); \
		group=$$(stat -c "%G" "$$d"); \
		mode=$$(stat -c "%a" "$$d"); \
		if [ "$$owner" = "root" ] && [ "$$group" = "admin" ] && [ "$$mode" = "775" ]; then \
			echo "📝 $$d root:admin 775"; \
		else \
			echo "❌ $$d $$owner:$$group $$mode"; \
		fi; \
	done