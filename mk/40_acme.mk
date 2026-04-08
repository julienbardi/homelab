# mk/40_acme.mk
# ACME certificate permission fixes

# Canonical ACME state location (overridable)
ACME_HOME ?= /var/lib/acme

.PHONY: check-acme-perms fix-acme-perms

check-acme-perms: ensure-run-as-root
	@if [ -d "$(ACME_HOME)" ]; then \
		echo "🔍 Verifying permissions under $(ACME_HOME)"; \
		$(run_as_root) find "$(ACME_HOME)" -ls | grep -E "key|cer|conf|csr|sh"; \
	else \
		echo "ℹ️ No ACME directory at $(ACME_HOME)"; \
	fi

fix-acme-perms: ensure-run-as-root
	@if [ -d "$(ACME_HOME)" ]; then \
		echo "🛡️ Enforcing root ownership and correct permissions on $(ACME_HOME)"; \
		$(run_as_root) chown -R $(ROUTER_SCRIPTS_OWNER):$(ROUTER_SCRIPTS_GROUP) "$(ACME_HOME)"; \
		\
		# Directories must be traversable (0755) \
		$(run_as_root) find "$(ACME_HOME)" -type d -exec chmod $(ROUTER_SCRIPTS_MODE) {} +; \
		\
		# Scripts (*.sh) must be executable (0755) \
		$(run_as_root) find "$(ACME_HOME)" -type f -name "*.sh" -exec chmod $(ROUTER_SCRIPTS_MODE) {} +; \
		\
		# Sensitive files (keys, certs, account data) remain locked down (0600) \
		$(run_as_root) find "$(ACME_HOME)" -type f ! -name "*.sh" -exec chmod 600 {} +; \
		\
		echo "✅ Permissions corrected."; \
	else \
		echo "⚠️ Cannot fix: $(ACME_HOME) does not exist."; \
	fi
