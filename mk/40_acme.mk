# mk/40_acme.mk
# ACME certificate permission fixes

# Canonical ACME state location (overridable)
ACME_HOME ?= /var/lib/acme

.PHONY: check-acme-perms

check-acme-perms: ensure-run-as-root
	@if [ -d "$(ACME_HOME)" ]; then \
	    echo "[acme][check] 🔍 Verifying permissions under $(ACME_HOME)"; \
	    $(run_as_root) find "$(ACME_HOME)" -ls | grep -E "key|cer|conf|csr|sh"; \
	else \
	    echo "[acme][check] ℹ️  No ACME directory at $(ACME_HOME)"; \
	fi
