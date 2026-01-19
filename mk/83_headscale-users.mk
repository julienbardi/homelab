# --------------------------------------------------------------------
# mk/83_headscale-users.mk — Headscale user management
# --------------------------------------------------------------------
# CONTRACT:
# - Headscale >= 0.28 (no namespaces).
# - Users are global; segmentation is enforced via ACLs.
# - Uses $(run_as_root) from mk/01_common.mk.
# - Idempotent and safe under parallel make.
# - No secrets written to disk.
# --------------------------------------------------------------------

HS_BIN ?= /usr/local/bin/headscale

# Global users to ensure
HEADSCALE_USERS := \
	lan \
	wan

.PHONY: headscale-users

headscale-users:
	@echo "[headscale] Ensuring users exist..."
	@for user in $(HEADSCALE_USERS); do \
		if ! $(run_as_root) "$(HS_BIN)" users list --output json \
			| jq -r '.[].name' | grep -qx "$$user"; then \
			echo "[headscale] Creating user $$user"; \
			$(run_as_root) "$(HS_BIN)" users create "$$user"; \
		else \
			echo "[headscale] User $$user already exists"; \
		fi; \
	done
