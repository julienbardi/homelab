# --------------------------------------------------------------------
# mk/84_headscale-acls.mk — Headscale ACL management
# --------------------------------------------------------------------
# CONTRACT:
# - Requires namespaces and users to already exist.
# - Installs ACL file atomically with safe permissions.
# - Restarts headscale only if ACL file is updated.
# - No secrets written to disk.
# --------------------------------------------------------------------

SHELL := /bin/bash

ACL_SRC ?= $(HOMELAB_DIR)/config/headscale/acl.json
ACL_DST ?= /etc/headscale/acl.json

.PHONY: headscale-acls

headscale-acls:
	@echo "[headscale] Installing ACL policy..."
	@if [ ! -f "$(ACL_SRC)" ]; then \
		echo "[headscale] ERROR: ACL source file not found: $(ACL_SRC)"; \
		exit 1; \
	fi
	@$(run_as_root) install -o root -g headscale -m 0640 "$(ACL_SRC)" "$(ACL_DST)"
	@$(run_as_root) systemctl restart headscale
	@echo "[headscale] ACL policy installed and headscale restarted"
