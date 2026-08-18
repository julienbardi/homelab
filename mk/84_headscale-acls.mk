# --------------------------------------------------------------------
# mk/84_headscale-acls.mk — Headscale ACL management
# --------------------------------------------------------------------
# CONTRACT:
# - Requires namespaces and users to already exist.
# - Installs ACL file atomically with safe permissions.
# - Restarts headscale only if ACL file is updated.
# - No secrets written to disk.
# --------------------------------------------------------------------

# VERSION: 2026.08.17-fix-headscale-acls-robust
ACL_SRC ?= $(REPO_ROOT)/config/headscale/acl.json
ACL_DST ?= /etc/headscale/acl.json

.PHONY: headscale-acls
headscale-acls: headscale-user headscale-dirs $(ACL_SRC)
	@echo "🛡️ Ensuring Headscale daemon is running and socket is ready..."; \
	sudo systemctl start headscale || true; \
	for i in {1..10}; do \
		if [ -S /var/run/headscale/headscale.sock ]; then break; fi; \
		sleep 0.5; \
	done; \
	echo "🛡️ Validating and Installing headscale ACL policy..."; \
	$(run_as_root) headscale policy check --file "$(ACL_SRC)" || { echo "❌ ACL validation failed"; exit 1; }; \
	RC=0; \
	$(run_as_root) env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(INSTALL_FILE_IF_CHANGED) -q \
		"" "" "$(ACL_SRC)" \
		"" "" "$(ACL_DST)" \
		root headscale 0640 || RC=$$?; \
	if [ $$RC -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		echo "🔄 ACL policy changed — flagging restart"; \
		touch "$(HEADSCALE_CHANGED_STAMP)"; \
	elif [ $$RC -ne 0 ]; then \
		echo "❌ ACL installation failed"; \
		exit $$RC; \
	fi; \
	echo "✅ Headscale ACL policy processed and validated"
