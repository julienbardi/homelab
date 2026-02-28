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

headscale-acls:
	@echo "🛂 Installing headscale ACL policy..."
	@if [ ! -f "$(ACL_SRC)" ]; then \
	    echo "❌ ACL source file not found: $(ACL_SRC)"; \
	    exit 1; \
	fi

	@$(run_as_root) bash -eu -c '\
	    changed=0; \
	    if [ ! -f "$(ACL_DST)" ]; then \
	        install -o root -g headscale -m 0640 "$(ACL_SRC)" "$(ACL_DST)"; \
	        changed=1; \
	    else \
	        if ! cmp -s "$(ACL_SRC)" "$(ACL_DST)"; then \
	            install -o root -g headscale -m 0640 "$(ACL_SRC)" "$(ACL_DST)"; \
	            changed=1; \
	        fi; \
	    fi; \
	    if [ $$changed -eq 1 ]; then \
	        echo "🔄 Restarting headscale due to ACL update"; \
	        systemctl daemon-reload; \
	        systemctl restart headscale; \
	    fi \
	'

	@echo "✅ Headscale ACL policy processed"
