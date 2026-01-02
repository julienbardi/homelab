# --------------------------------------------------------------------
# mk/83_headscale-users.mk — Headscale user management
# --------------------------------------------------------------------
# CONTRACT:
# - Requires namespaces to already exist.
# - Uses $(run_as_root) from mk/01_common.mk.
# - Idempotent: creates users only if missing.
# - No secrets written to disk.
# - Safe under parallel make.
# --------------------------------------------------------------------

SHELL := /bin/bash

HS_BIN ?= /usr/local/bin/headscale

# Users to ensure, grouped by namespace
HEADSCALE_USERS := \
	bardi-lan:lan \
	bardi-wan:wan

.PHONY: headscale-users

headscale-users:
	@echo "[headscale] Ensuring users exist..."
	@for entry in $(HEADSCALE_USERS); do \
		ns=$${entry%%:*}; \
		user=$${entry##*:}; \
		if ! $(run_as_root) "$(HS_BIN)" users list --namespace "$$ns" | awk '{print $$1}' | grep -qx "$$user"; then \
			echo "[headscale] Creating user $$user in namespace $$ns"; \
			$(run_as_root) "$(HS_BIN)" users create --namespace "$$ns" "$$user"; \
		else \
			echo "[headscale] User $$user already exists in namespace $$ns"; \
		fi; \
	done
