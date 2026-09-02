# ============================================================================
# mk/05_bootstrap_acme.mk — ACME Identity + acme.sh Installer
# ============================================================================
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
#   4. Re-run `make acme-bootstrap` (from mk/40_acme.mk).
#   5. Re-issue all certificates and redeploy them.
#
# ACME supports bootstrap and upgrade only.
# No uninstall target must ever exist.
# ============================================================================


# ------------------------------------------------------------
# ACME_HOME is defined in mk/config.mk
# ------------------------------------------------------------
ACME_BIN     := $(ACME_HOME)/acme.sh
ACME_VERSION := v3.1.4

# ------------------------------------------------------------
# Ensure ACME_HOME exists (identity directory)
# ------------------------------------------------------------
.PHONY: acme-ensure-dirs
acme-ensure-dirs:
	@$(run_as_root) install -d -m 0700 -o $(ROOT_UID) -g $(ROOT_GID) "$(ACME_HOME)"

# ------------------------------------------------------------
# Install or update acme.sh (sudo-safe mode)
# ------------------------------------------------------------
ACME_SRC := $(HOME)/src/acme.sh

.PHONY: acme-install
acme-install: acme-ensure-dirs
	@if ! command -v curl >/dev/null 2>&1; then \
		echo "❌ curl missing — required for ACME bootstrap"; \
		exit 1; \
	fi; \
	if ! command -v git >/dev/null 2>&1; then \
		echo "❌ git missing — required for ACME source sync"; \
		exit 1; \
	fi; \
	\
	CURRENT_VER="$$( $(run_as_root) sh -c 'if [ -x "$(ACME_BIN)" ]; then "$(ACME_BIN)" --version | tail -n 1 | xargs; else echo none; fi' )"; \
	FORCE_REINSTALL=0; \
	\
	if ! $(run_as_root) grep -q "LE_WORKING_DIR" "$(ACME_HOME)/account.conf" 2>/dev/null; then \
		if [ "$$CURRENT_VER" != "none" ]; then \
			echo "⚠️ ACME installed but not sudo-safe — forcing reinstall"; \
		fi; \
		FORCE_REINSTALL=1; \
	fi; \
	\
	if [ "$$CURRENT_VER" != "$(ACME_VERSION)" ] || [ "$$FORCE_REINSTALL" = "1" ]; then \
		if [ "$$VERBOSE" = "1" ]; then \
			echo "🔄 Installing acme.sh $(ACME_VERSION) (sudo-safe mode)..."; \
		fi; \
		$(call git_clone_or_fetch,$(ACME_SRC),https://github.com/acmesh-official/acme.sh.git,master); \
		$(run_as_root) sh -euo pipefail -c '\
			cd "$(ACME_SRC)"; \
			LE_FORCE_SUDO=1 ./acme.sh \
				--install \
				--nocron \
				--home "$(ACME_HOME)" \
				--accountemail "$(DOMAIN)@$(DOMAIN)" \
				--force >/dev/null; \
			chmod 700 "$(ACME_HOME)"; \
			chmod 755 "$(ACME_HOME)/acme.sh"; \
			find "$(ACME_HOME)/dnsapi" -type f -exec chmod 755 {} \;; \
			find "$(ACME_HOME)" -type f -name "*.cer" -exec chmod 644 {} \;; \
			find "$(ACME_HOME)" -type f -name "*.key" -exec chmod 600 {} \;; \
			TMP="$$(mktemp)"; \
			printf "LE_WORKING_DIR=\"%s\"\n" "$(ACME_HOME)" > "$$TMP"; \
			RC=0; \
			"$(INSTALL_FILE_IF_CHANGED)" -q \
				"" "" "$$TMP" \
				"" "" "$(ACME_HOME)/account.conf" \
				"$(ROOT_UID)" "$(ROOT_GID)" 600 || RC=$$?; \
			if [ "$$RC" -ne 0 ] && [ "$$RC" -ne "$(INSTALL_IF_CHANGED_EXIT_CHANGED)" ]; then \
				echo "❌ IFC failed (exit $$RC)"; \
				exit $$RC; \
			fi; \
			rm -f "$$TMP"; \
		'; \
	else \
		echo "✅ acme.sh $$CURRENT_VER already installed (sudo-safe)."; \
	fi


# ------------------------------------------------------------
# Inject Infomaniak API token (idempotent, secrets-aware)
# ------------------------------------------------------------
.PHONY: acme-write-infomaniak-token
acme-write-infomaniak-token: secrets-ready
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
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🔐 Installing Infomaniak API token into $(ACME_HOME)/account.conf"; fi;\
		RC=0; \
		$(run_as_root) "$(INSTALL_FILE_IF_CHANGED)" -q \
			"" "" "$$TMP" \
			"" "" "$(ACME_HOME)/account.conf" \
			"$(ROOT_UID)" "$(ROOT_GID)" 600 || RC=$$?; \
		if [ "$$RC" -ne 0 ] && [ "$$RC" -ne "$(INSTALL_IF_CHANGED_EXIT_CHANGED)" ]; then \
			echo "❌ IFC failed (exit $$RC)"; \
			exit $$RC; \
		fi; \
		rm -f "$$TMP"; \
	')
