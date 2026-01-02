# --------------------------------------------------------------------
# mk/82_headscale-namespaces.mk — Headscale namespace management
# --------------------------------------------------------------------
# CONTRACT:
# - Requires headscale service to be installed and running.
# - Uses $(run_as_root) from mk/01_common.mk.
# - Idempotent: creates namespaces only if missing.
# - Safe under parallel make.
# --------------------------------------------------------------------

SHELL := /bin/bash

HS_BIN ?= /usr/local/bin/headscale

HEADSCALE_NAMESPACES := \
	bardi-lan \
	bardi-wan

.PHONY: headscale-namespaces

headscale-namespaces:
	@echo "[headscale] Ensuring namespaces exist..."
	@for ns in $(HEADSCALE_NAMESPACES); do \
		if ! $(run_as_root) "$(HS_BIN)" namespaces list | awk '{print $$1}' | grep -qx "$$ns"; then \
			echo "[headscale] Creating namespace $$ns"; \
			$(run_as_root) "$(HS_BIN)" namespaces create "$$ns"; \
		else \
			echo "[headscale] Namespace $$ns already exists"; \
		fi; \
	done
