# --------------------------------------------------------------------
# mk/84_headscale-acls.mk — Headscale ACL management
# --------------------------------------------------------------------
# CONTRACT:
# - Requires namespaces and users to already exist.
# - Installs ACL file atomically with safe permissions.
# - Restarts headscale only if ACL file is updated.
# - No secrets written to disk.
# --------------------------------------------------------------------

ACL_SRC ?= $(REPO_ROOT)/config/headscale/acl.json
ACL_DST ?= /etc/headscale/acl.json

.PHONY: headscale-acls
headscale-acls: ensure-run-as-root $(ACL_SRC)
	@echo "🛂 Validating and Installing headscale ACL policy..."
	@# Corrected flag from --policy to --file
	@$(run_as_root) headscale policy check --file $(ACL_SRC) || { echo "❌ ACL validation failed"; exit 1; }
	@# Install with change tracking
	@$(run_as_root) env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(INSTALL_FILE_IF_CHANGED) -q \
		"" "" "$(ACL_SRC)" \
		"" "" "$(ACL_DST)" \
		root headscale 0640; \
		RC=$$?; \
		if [ $$RC -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
			echo "🔄 ACL policy changed — flagging restart"; \
			touch "$(HEADSCALE_CHANGED_STAMP)"; \
		elif [ $$RC -ne 0 ]; then \
			echo "❌ ACL installation failed"; \
			exit $$RC; \
		fi
	@echo "✅ Headscale ACL policy processed and validated"