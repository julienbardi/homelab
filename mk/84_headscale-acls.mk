# --------------------------------------------------------------------
# mk/84_headscale-acls.mk — Headscale ACL management
# --------------------------------------------------------------------
# CONTRACT:
# - Requires namespaces and users to already exist.
# - Installs ACL file atomically with safe permissions.
# - Restarts headscale only if ACL file is updated.
# - No secrets written to disk.
# --------------------------------------------------------------------

ACL_SRC ?= $(HOMELAB_DIR)/config/headscale/acl.json
ACL_DST ?= /etc/headscale/acl.json

.PHONY: headscale-acls

headscale-acls:
	@echo "[headscale] Installing ACL policy..."
	@if [ ! -f "$(ACL_SRC)" ]; then \
		echo "[headscale] ERROR: ACL source file not found: $(ACL_SRC)"; \
		exit 1; \
	fi

	@$(run_as_root) bash -c '\
		changed=0; \
		if [ ! -f "$(ACL_DST)" ]; then \
			echo "[headscale] No existing ACL — installing fresh copy"; \
			install -o root -g headscale -m 0640 "$(ACL_SRC)" "$(ACL_DST)"; \
			changed=1; \
		else \
			if ! cmp -s "$(ACL_SRC)" "$(ACL_DST)"; then \
				echo "[headscale] ACL changed — installing new version"; \
				install -o root -g headscale -m 0640 "$(ACL_SRC)" "$(ACL_DST)"; \
				changed=1; \
			else \
				echo "[headscale] ACL unchanged — nothing to do"; \
			fi; \
		fi; \
		if [ $$changed -eq 1 ]; then \
			echo "[headscale] Restarting headscale due to ACL update"; \
			systemctl daemon-reload; \
			systemctl restart headscale; \
		fi \
	'

	@echo "[headscale] ACL policy processed"

