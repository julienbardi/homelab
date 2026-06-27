# mk/05_bootstrap_acme.mk
# --------------------------------------------------------------------
# IMPORTANT: ACME MUST NEVER BE UNINSTALLED
#
# ACME_HOME (/var/lib/acme) contains:
#   - The ACME account private key (account.key)
#   - The ACME registration metadata (account.conf)
#   - The server keypair used for certificate issuance
#
# These files are the identity of this machine to the ACME CA.
# Deleting them would:
#   - Destroy the ACME account identity
#   - Force creation of a new account keypair
#   - Invalidate all existing certificates
#   - Break every dependent service (dnsdist, DoH, nginx, etc.)
#
# ROTATION POLICY:
#   - The ACME account key MUST NOT be rotated automatically.
#   - Rotation is only allowed manually, in exceptional cases
#     (e.g., confirmed key compromise).
#
# HOW TO ROTATE (manual, destructive, last-resort):
#   1. Stop all services depending on certificates.
#   2. Backup /var/lib/acme (for forensic purposes only).
#   3. Delete ONLY the ACME account identity:
#        rm -f /var/lib/acme/account.key /var/lib/acme/account.conf
#   4. Re-run `make acme-bootstrap` to create a new ACME account.
#   5. Re-issue all certificates and redeploy them.
#
# NOTE:
#   - Rotation invalidates all existing certificates.
#   - Rotation requires full redeployment of TLS material.
#   - Therefore: DO NOT ROTATE unless absolutely necessary.
#
# ACME supports bootstrap and upgrade only.
# No uninstall target must ever exist.
# --------------------------------------------------------------------

# ACME_HOME is defined in mk/config.mk
ACME_BIN     := $(ACME_HOME)/acme.sh
ACME_VERSION := v3.1.4

.PHONY: acme-bootstrap acme-install acme-ensure-dirs

acme-bootstrap: acme-ensure-dirs acme-install acme-write-infomaniak-token
	@echo "✅ ACME bootstrap complete"

acme-ensure-dirs: | $(run_as_root)
	@$(run_as_root) install -d -m 0700 -o $(ROOT_UID) -g $(ROOT_GID) "$(ACME_HOME)"

ACME_SRC := $(HOME)/src/acme.sh

acme-install: | $(run_as_root)
	@if ! command -v curl >/dev/null 2>&1; then \
		echo "❌ curl missing — required for ACME bootstrap"; \
		exit 1; \
	fi; \
	if ! command -v git >/dev/null 2>&1; then \
		echo "❌ git missing — required for ACME source sync"; \
		exit 1; \
	fi; \
	CURRENT_VER="$$( $(run_as_root) sh -c 'test -x "$(ACME_BIN)" && "$(ACME_BIN)" --version | tail -n 1 | xargs || echo none' )"; \
	FORCE_REINSTALL=0; \
	if ! $(run_as_root) grep -q "LE_WORKING_DIR" "$(ACME_HOME)/account.conf" 2>/dev/null; then \
		echo "⚠️ ACME not installed in sudo-safe mode — forcing reinstall"; \
		FORCE_REINSTALL=1; \
	fi; \
	if [ "$$CURRENT_VER" != "$(ACME_VERSION)" ] || [ "$$FORCE_REINSTALL" = "1" ]; then \
		echo "🔄 Installing ACME (sudo-safe mode)..."; \
		$(call git_clone_or_fetch,$(ACME_SRC),https://github.com/acmesh-official/acme.sh.git,master); \
		$(run_as_root) sh -c '\
			cd "$(ACME_SRC)"; \
			LE_FORCE_SUDO=1 ./acme.sh \
				--install \
				--nocron \
				--home "$(ACME_HOME)" \
				--accountemail "$(DOMAIN)@$(DOMAIN)" \
				--force; \
			chmod 700 "$(ACME_HOME)"; \
			chmod 755 "$(ACME_HOME)/acme.sh"; \
			find "$(ACME_HOME)/dnsapi" -type f -exec chmod 755 {} \;; \
			find "$(ACME_HOME)" -type f -name "*.cer" -exec chmod 644 {} \;; \
			find "$(ACME_HOME)" -type f -name "*.key" -exec chmod 600 {} \;; \
		'; \
	else \
		echo "✅ acme.sh $$CURRENT_VER already installed (sudo-safe)."; \
	fi

# --------------------------------------------------------------------
# ACME: Inject Infomaniak API token (idempotent, secrets-aware)
# --------------------------------------------------------------------
.PHONY: acme-write-infomaniak-token
acme-write-infomaniak-token: secrets-ready | $(INSTALL_FILES_IF_CHANGED) $(run_as_root)
	@$(call WITH_SECRETS, sh -euo pipefail -c '\
		TOKEN="$$INFOMANIAK_API_TOKEN"; \
		if [ -z "$$TOKEN" ]; then \
			echo "❌ ERROR: INFOMANIAK_API_TOKEN missing from secrets.enc.yaml"; \
			exit 1; \
		fi; \
		\
		TMP="$$(mktemp)"; \
		printf "INFOMANIAK_API_TOKEN=\"%s\"\n" "$$TOKEN" > "$$TMP"; \
		\
		echo "🔐 Installing Infomaniak API token into $(ACME_HOME)/account.conf"; \
		RC=0; \
		$(run_as_root) "$(INSTALL_FILE_IF_CHANGED)" -q \
			"" "" "$$TMP" \
			"" "" "$(ACME_HOME)/account.conf" \
			"$(ROOT_UID)" "$(ROOT_GID)" 600 || RC=$$?; \
		if [ "$$RC" -ne 0 ] && [ "$$RC" -ne "$(INSTALL_IF_CHANGED_EXIT_CHANGED)" ]; then \
			echo "❌ IFC failed for $$TARGET (exit $$RC)"; \
			exit $$RC; \
		fi; \
		rm -f "$$TMP"; \
	')
