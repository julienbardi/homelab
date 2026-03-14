# mk/40_acme.mk
# ACME certificate permission fixes

# Canonical ACME state location (overridable)
ACME_HOME ?= /var/lib/acme

.PHONY: check-acme-perms fix-acme-perms

check-acme-perms: ensure-run-as-root
	@if [ -d "$(ACME_HOME)" ]; then \
		echo "[acme][check] 🔍 Verifying permissions under $(ACME_HOME)"; \
		$(run_as_root) find "$(ACME_HOME)" -ls | grep -E "key|cer|conf|csr|sh"; \
	else \
		echo "[acme][check] ℹ️  No ACME directory at $(ACME_HOME)"; \
	fi

fix-acme-perms: ensure-run-as-root
	@if [ -d "$(ACME_HOME)" ]; then \
		echo "[acme][fix] 🛡️  Enforcing root ownership and strict permissions on $(ACME_HOME)"; \
		$(run_as_root) chown -R root:root "$(ACME_HOME)"; \
		$(run_as_root) find "$(ACME_HOME)" -type d -exec chmod 700 {} +; \
		$(run_as_root) find "$(ACME_HOME)" -type f -exec chmod 600 {} +; \
		$(run_as_root) find "$(ACME_HOME)" -name "*.sh" -exec chmod 700 {} +; \
		echo "[acme][fix] ✅ Permissions locked down."; \
	else \
		echo "[acme][fix] ⚠️  Cannot fix: $(ACME_HOME) does not exist."; \
	fi