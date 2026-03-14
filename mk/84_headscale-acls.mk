# --------------------------------------------------------------------
# mk/84_headscale-acls.mk — Headscale ACL management
# --------------------------------------------------------------------
# CONTRACT:
# - Requires namespaces and users to already exist.
# - Installs ACL file atomically with safe permissions.
# - Restarts headscale only if ACL file is updated.
# - No secrets written to disk.
# --------------------------------------------------------------------

ACL_SRC ?= $(MAKEFILE_DIR)config/headscale/acl.json
ACL_DST ?= /etc/headscale/acl.json

.PHONY: headscale-acls
headscale-acls: ensure-run-as-root $(ACL_SRC)
	@echo "🛂 Installing headscale ACL policy..."
	@$(run_as_root) env CHANGED_EXIT_CODE=3 \
		$(INSTALL_FILE_IF_CHANGED) -q \
		"" "" "$(ACL_SRC)" \
		"" "" "$(ACL_DST)" \
		root headscale 0640 \
		|| [ $$? -eq 3 ]
	@echo "✅ Headscale ACL policy processed"