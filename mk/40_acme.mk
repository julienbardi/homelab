# mk/40_acme.mk
# ACME certificate management

ACME_HOME := /var/lib/acme
ACME_BIN  := $(ACME_HOME)/acme.sh

.PHONY: acme-renew-all fix-acme-perms

fix-acme-perms: ensure-run-as-root
	@echo "🛡️ Enforcing root:root ownership on $(ACME_HOME)"
	@$(run_as_root) chown -R 0:0 "$(ACME_HOME)"
	@$(run_as_root) find "$(ACME_HOME)" -type d -exec chmod 0700 {} +
	@$(run_as_root) find "$(ACME_HOME)" -type f -name "*.sh" -exec chmod 0755 {} +
	@$(run_as_root) find "$(ACME_HOME)" -type f ! -name "*.sh" -exec chmod 0600 {} +

acme-renew-all: ensure-run-as-root
	@echo "🔄 Consolidating ACME state and running lifecycle..."
	@$(run_as_root) env -u SUDO_USER -u SUDO_UID -u SUDO_GID -u SUDO_COMMAND \
		ACME_HOME="$(ACME_HOME)" \
		sh -c ' \
			if [ -d "/root/.acme.sh/bardi.ch_ecc" ]; then \
				echo "🚚 Syncing June certificates into $(ACME_HOME)"; \
				cp -rf /root/.acme.sh/* $(ACME_HOME)/; \
				chown -R 0:0 $(ACME_HOME); \
				find $(ACME_HOME) -type d -exec chmod 0700 {} +; \
				find $(ACME_HOME) -type f -name "*.sh" -exec chmod 0755 {} +; \
				find $(ACME_HOME) -type f ! -name "*.sh" -exec chmod 0600 {} +; \
			fi && \
			echo "🧹 Clearing intermediate store..." && \
			rm -rf /var/lib/ssl/canonical/* && \
			$(REPO_ROOT)scripts/deploy_certificates.sh renew && \
			$(REPO_ROOT)scripts/deploy_certificates.sh prepare && \
			$(REPO_ROOT)scripts/deploy_certificates.sh deploy dnsdist \
		'