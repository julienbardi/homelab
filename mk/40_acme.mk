# mk/40_acme.mk
# ACME certificate permission fixes

# Canonical ACME state location (overridable)
ACME_HOME ?= /var/lib/acme

# Group allowed to read certificates
ACME_GROUP ?= ssl-cert

.PHONY: fix-acme-perms check-acme-perms

fix-acme-perms: harden-groups ensure-run-as-root
	@if [ -d "$(ACME_HOME)" ]; then \
	    echo "[acme][fix] 🔧 Fixing permissions under $(ACME_HOME)"; \
	    $(run_as_root) find "$(ACME_HOME)" -type f -name "*.key" -exec chmod 600 {} \; ; \
	    $(run_as_root) find "$(ACME_HOME)" -type f \( -name "*.cer" -o -name "*.conf" -o -name "*.csr" -o -name "*.csr.conf" \) -exec chmod 644 {} \; ; \
	    $(run_as_root) find "$(ACME_HOME)" -type f -name "*.sh" -exec chmod 750 {} \; ; \
	    $(run_as_root) find "$(ACME_HOME)" -type d -exec chmod 750 {} \; ; \
	    $(run_as_root) chown -R root:$(ACME_GROUP) "$(ACME_HOME)"; \
	    echo "[acme][fix] ✅ Permissions corrected at $$(date '+%Y-%m-%d %H:%M:%S')"; \
	else \
	    echo "[acme][fix] ℹ️  No ACME directory at $(ACME_HOME) — skipping"; \
	fi

check-acme-perms: ensure-run-as-root
	@if [ -d "$(ACME_HOME)" ]; then \
	    echo "[acme][check] 🔍 Verifying permissions under $(ACME_HOME)"; \
	    $(run_as_root) find "$(ACME_HOME)" -ls | grep -E "key|cer|conf|csr|sh"; \
	else \
	    echo "[acme][check] ℹ️  No ACME directory at $(ACME_HOME)"; \
	fi
