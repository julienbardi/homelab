# mk/05_bootstrap_acme.mk — ACME bootstrap (authoritative)
ACME_BOOTSTRAP_DIR = $(ACME_HOME)
ACME_INSTALLER_URL := https://get.acme.sh

.PHONY: acme-bootstrap acme-install acme-ensure-dirs acme-fix-perms

acme-bootstrap: ensure-run-as-root acme-ensure-dirs acme-install acme-fix-perms
	@echo "✅ ACME bootstrap complete"

acme-ensure-dirs:
	@echo "📁 Ensuring ACME_HOME exists at $(ACME_BOOTSTRAP_DIR)"
	@$(run_as_root) install -d -m 0750 -o julie -g admin $(ACME_BOOTSTRAP_DIR)

acme-install:
	@if [ ! -f "$(ACME_BOOTSTRAP_DIR)/acme.sh" ]; then \
		echo "⬇️ Installing acme.sh into $(ACME_BOOTSTRAP_DIR)"; \
		curl -s $(ACME_INSTALLER_URL) | sh -s email=admin@bardi.ch; \
		echo "📦 Moving acme.sh installation into $(ACME_BOOTSTRAP_DIR)"; \
		mv /home/julie/.acme.sh/* $(ACME_BOOTSTRAP_DIR)/; \
		rmdir /home/julie/.acme.sh || true; \
	else \
		echo "ℹ️ acme.sh already present — skipping install"; \
	fi

acme-fix-perms:
	@echo "🛡️ Fixing ACME permissions"
	@$(run_as_root) chown -R julie:admin $(ACME_BOOTSTRAP_DIR)
	@$(run_as_root) find $(ACME_BOOTSTRAP_DIR) -type d -exec chmod 0750 {} +
	@$(run_as_root) find $(ACME_BOOTSTRAP_DIR) -type f -name "*.sh" -exec chmod 0755 {} +
	@$(run_as_root) find $(ACME_BOOTSTRAP_DIR) -type f ! -name "*.sh" -exec chmod 0600 {} +
	@echo "🔐 Permissions OK"
