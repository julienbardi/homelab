# ============================================================================
# mk/40_acme.mk — ACME Subsystem (Authoritative)
# ============================================================================
# Responsibilities:
#   - ACME bootstrap (scripts + systemd units)
#   - ACME initial issuance (systemd-managed)
#   - ACME renewal (systemd-managed, daily)
#   - ACME migration (dangerous, one-time)
#
# This file MUST NOT:
#   - deploy canonical certificates
#   - manage canonical cert stamps
#   - interact with mk/50_certs.mk except via ACME output
#
# All ACME paths MUST be defined in mk/config.mk.
# ============================================================================

# ------------------------------------------------------------
# Fail-fast validation of ACME paths (operator-friendly)
# ------------------------------------------------------------
# Real newline for foreach expansion
define NL


endef
.PHONY: acme-validate-paths
acme-validate-paths:
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🔍 Validating ACME configuration"; fi; \
	$(foreach var,ACME_ISSUE_SERVICE ACME_RENEW_SERVICE ACME_RENEW_TIMER ACME_ISSUE_SCRIPT ACME_RENEW_SCRIPT,\
		if [ -z "$($(var))" ]; then \
			echo "❌ $(var) is undefined in mk/config.mk"; exit 1; \
		fi; \
		if ! bash -c 'echo $$$(var)' | grep -q .; then \
			echo "❌ $(var) is not exported to the shell"; \
			echo "   ➡️ Add: export $(var) in mk/config.mk"; \
			exit 1; \
		fi; \
	$(NL)) \
	if [ "$(VERBOSE)" -ge 1 ]; then echo "🟢 ACME paths validated (Make + shell)"; fi

# ============================================================================
# 1. ACME Bootstrap (idempotent)
# ============================================================================
# Installs:
#   - ACME scripts (issue + renew)
#   - ACME systemd units (issue + renew)
#   - ACME renewal timer
#
# This is the ONLY correct way to install ACME infrastructure.
# ============================================================================

define INSTALL_ACME_FILES
	CHANGED=0; \
	TMP_ISSUE_SVC="$$(mktemp)"; \
	TMP_ISSUE_TMR="$$(mktemp)"; \
	TMP_RENEW_SVC="$$(mktemp)"; \
	TMP_RENEW_TMR="$$(mktemp)"; \
	\
	envsubst < "$(REPO_ROOT)/config/systemd/acme-issue.service.in" > "$$TMP_ISSUE_SVC"; \
	envsubst < "$(REPO_ROOT)/config/systemd/acme-issue.timer.in"   > "$$TMP_ISSUE_TMR"; \
	envsubst < "$(REPO_ROOT)/config/systemd/acme-renew.service.in" > "$$TMP_RENEW_SVC"; \
	envsubst < "$(REPO_ROOT)/config/systemd/acme-renew.timer.in"   > "$$TMP_RENEW_TMR"; \
	\
	for spec in \
		"$(REPO_ROOT)/scripts/acme-issue.sh:$(ACME_ISSUE_SCRIPT):0755" \
		"$(REPO_ROOT)/scripts/acme-renew.sh:$(ACME_RENEW_SCRIPT):0755" \
		"$$TMP_ISSUE_SVC:$(ACME_ISSUE_SERVICE):0644" \
		"$$TMP_ISSUE_TMR:$(ACME_ISSUE_TIMER):0644" \
		"$$TMP_RENEW_SVC:$(ACME_RENEW_SERVICE):0644" \
		"$$TMP_RENEW_TMR:$(ACME_RENEW_TIMER):0644"; \
	do \
		src="$${spec%%:*}"; \
		rest="$${spec#*:}"; \
		dst="$${rest%%:*}"; \
		mode="$${rest#*:}"; \
		if ! cmp -s "$$src" "$$dst" 2>/dev/null; then \
			cp "$$src" "$$dst"; \
			chown root:root "$$dst"; \
			chmod "$$mode" "$$dst"; \
			CHANGED=1; \
		fi; \
	done; \
	\
	rm -f "$$TMP_ISSUE_SVC" "$$TMP_ISSUE_TMR" "$$TMP_RENEW_SVC" "$$TMP_RENEW_TMR"; \
	\
	if [ "$$CHANGED" -eq 1 ]; then \
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🔄 Reloading systemd"; fi; \
		systemctl daemon-reload; \
	fi; \
	\
	if ! systemctl is-enabled --quiet acme-renew.timer; then \
		systemctl enable --now acme-renew.timer; \
		CHANGED=1; \
	fi
endef

.PHONY: acme-bootstrap
acme-bootstrap: acme-validate-paths
	@$(run_as_root) bash -euo pipefail -c '\
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🔧 Installing ACME scripts and rendering systemd units"; fi; \
		$(INSTALL_ACME_FILES); \
		if [ "$$CHANGED" -eq 1 ] || [ "$(VERBOSE)" -ge 1 ]; then \
			echo "🟢 ACME bootstrap complete"; \
		fi; \
	'

# ============================================================================
# ACME Script Validation
# ============================================================================
.PHONY: acme-validate-scripts
acme-validate-scripts:
	@bash -euo pipefail -c '\
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🔍 Validating ACME scripts"; fi; \
		for f in "$(ACME_ISSUE_SCRIPT)" "$(ACME_RENEW_SCRIPT)"; do \
			if [ ! -f "$$f" ]; then \
				echo "❌ Missing ACME script: $$f" >&2; \
				exit 1; \
			fi; \
			if [ ! -x "$$f" ]; then \
				echo "❌ ACME script not executable: $$f" >&2; \
				exit 1; \
			fi; \
		done; \
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🟢 ACME scripts validated"; fi; \
	'

# ============================================================================
# ACME Systemd Unit Validation
# ============================================================================
.PHONY: acme-validate-units
acme-validate-units:
	@bash -euo pipefail -c '\
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🔍 Validating ACME systemd units"; fi; \
		for u in "$(ACME_ISSUE_SERVICE)" "$(ACME_ISSUE_TIMER)" "$(ACME_RENEW_SERVICE)" "$(ACME_RENEW_TIMER)"; do \
			if [ ! -f "$$u" ]; then \
				echo "❌ Missing ACME systemd unit: $$u" >&2; \
				exit 1; \
			fi; \
		done; \
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🟢 ACME systemd units validated"; fi; \
	'

# ============================================================================
# ACME Systemd Syntax Validation
# ============================================================================
.PHONY: acme-validate-systemd
acme-validate-systemd: acme-bootstrap
	@$(run_as_root) bash -euo pipefail -c '\
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🔍 Validating systemd syntax"; fi; \
		systemctl daemon-reload; \
		for u in acme-issue.service acme-renew.service acme-renew.timer; do \
			if ! systemctl cat "$$u" >/dev/null 2>&1; then \
				echo "❌ systemd cannot load $$u" >&2; \
				exit 1; \
			fi; \
		done; \
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🟢 systemd syntax validated"; fi; \
	'

# ============================================================================
# ACME Timer Validation
# ============================================================================
.PHONY: acme-validate-timer
acme-validate-timer: acme-bootstrap
	@$(run_as_root) bash -euo pipefail -c '\
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🔍 Validating ACME renewal timer"; fi; \
		if ! systemctl is-enabled --quiet acme-renew.timer; then \
			echo "❌ acme-renew.timer is not enabled" >&2; \
			exit 1; \
		fi; \
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🟢 ACME renewal timer validated"; fi; \
	'

# ============================================================================
# ACME_HOME Validation
# ============================================================================
.PHONY: acme-validate-home
acme-validate-home:
	@$(run_as_root) bash -euo pipefail -c '\
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🔍 Validating ACME_HOME"; fi; \
		if [ ! -d "$(ACME_HOME)" ]; then \
			echo "❌ ACME_HOME missing: $(ACME_HOME)" >&2; \
			exit 1; \
		fi; \
		if [ ! -f "$(ACME_HOME)/acme.sh" ]; then \
			echo "❌ acme.sh missing in ACME_HOME" >&2; \
			exit 1; \
		fi; \
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🟢 ACME_HOME validated"; fi; \
	'

# ============================================================================
# Infomaniak Token Validation
# ============================================================================
.PHONY: acme-validate-token
acme-validate-token:
	@$(run_as_root) bash -euo pipefail -c '\
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🔍 Validating Infomaniak token"; fi; \
		if [ ! -f "$(ACME_HOME)/account.conf" ]; then \
			echo "❌ ACME account.conf missing: $(ACME_HOME)/account.conf" >&2; \
			exit 1; \
		fi; \
		if ! grep -q "INFOMANIAK_API_TOKEN" "$(ACME_HOME)/account.conf"; then \
			echo "❌ Infomaniak token missing from $(ACME_HOME)/account.conf" >&2; \
			exit 1; \
		fi; \
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🟢 Infomaniak token validated"; fi; \
	'

# ============================================================================
# Issuance Directory Validation
# ============================================================================
.PHONY: acme-validate-issuance
acme-validate-issuance:
	@$(run_as_root) bash -euo pipefail -c '\
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🔍 Validating ACME issuance directory"; fi; \
		if [ ! -d "$(ACME_HOME)/$(DOMAIN)_ecc" ]; then \
			echo "❌ No issuance directory found: $(ACME_HOME)/$(DOMAIN)_ecc" >&2; \
			exit 1; \
		fi; \
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🟢 ACME issuance directory validated"; fi; \
	'

# ============================================================================
# ACME Convergence Target
# ============================================================================
.PHONY: acme-selftest
acme-selftest: \
	acme-validate-paths \
	acme-validate-scripts \
	acme-validate-units \
	acme-validate-systemd \
	acme-validate-timer \
	acme-validate-home \
	acme-validate-token \
	acme-validate-issuance
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🟢 ACME subsystem converged"; fi

# ============================================================================
# 2. ACME Initial Issuance (safe, idempotent, synchronous)
# ============================================================================
.PHONY: acme-issue
acme-issue: acme-bootstrap ddns-env acme-install acme-write-infomaniak-token
	@$(run_as_root) bash -euo pipefail -c '\
		if [ ! -f "$(ACME_HOME)/$(DOMAIN)_ecc/fullchain.pem" ]; then \
			echo "🚀 Issuing ACME certificate synchronously via acme.sh..."; \
			export HOME="$(ACME_HOME)"; \
			unset SUDO_USER; \
			/var/lib/acme/acme.sh --issue --server letsencrypt --dns dns_infomaniak -d "$(DOMAIN)" -d "*.$(DOMAIN)" --home "$(ACME_HOME)" || true; \
		else \
			if [ "$(VERBOSE)" -ge 1 ]; then echo "🟢 ACME certificate already exists"; fi; \
		fi; \
		if [ -f "$(ACME_HOME)/$(DOMAIN)_ecc/fullchain.cer" ]; then \
			rm -f "$(ACME_HOME)/$(DOMAIN)_ecc/fullchain.pem"; \
			cp "$(ACME_HOME)/$(DOMAIN)_ecc/fullchain.cer" "$(ACME_HOME)/$(DOMAIN)_ecc/fullchain.pem"; \
			echo "🟢 Updated fullchain.pem from fullchain.cer"; \
		fi; \
		ENV_FILE="$(ACME_HOME)/acme-env.sh"; \
		{ \
			echo "export SSL_KEY_ECC=\"$(ACME_HOME)/$(DOMAIN)_ecc/$(DOMAIN).key\""; \
			echo "export SSL_CERT_ECC=\"$(ACME_HOME)/$(DOMAIN)_ecc/$(DOMAIN).cer\""; \
			echo "export SSL_CA_ECC=\"$(ACME_HOME)/$(DOMAIN)_ecc/ca.cer\""; \
			echo "export SSL_FULLCHAIN_ECC=\"$(ACME_HOME)/$(DOMAIN)_ecc/fullchain.pem\""; \
		} > "$$ENV_FILE"; \
		chmod 600 "$$ENV_FILE"; \
		STAMP_PATH="$(call STAMP_PATH_FROM_KEY,acme-issue)"; \
		_dir="$$(dirname "$$STAMP_PATH")"; \
		mkdir -p "$$_dir"; \
		_sha="$$(sha256sum "$$ENV_FILE" | awk '\''{print $$1}'\'')"; \
		{ \
			echo "version=1"; \
			echo "sha256=$$_sha"; \
			echo "owner=root"; \
			echo "group=root"; \
			echo "perm=600"; \
			echo "type=regular"; \
		} > "$$STAMP_PATH.tmp"; \
		mv -f "$$STAMP_PATH.tmp" "$$STAMP_PATH"; \
	'

export SSL_KEY_ECC = $(ACME_HOME)/$(DOMAIN)_ecc/$(DOMAIN).key
export SSL_CERT_ECC = $(ACME_HOME)/$(DOMAIN)_ecc/$(DOMAIN).cer
export SSL_CA_ECC = $(ACME_HOME)/$(DOMAIN)_ecc/ca.cer
export SSL_FULLCHAIN_ECC = $(ACME_HOME)/$(DOMAIN)_ecc/fullchain.pem

.PHONY: acme-issue-sync
acme-issue-sync: acme-issue

# ============================================================================
# 3. ACME Renewal (safe, idempotent, daily)
# ============================================================================
.PHONY: acme-renew
acme-renew: acme-issue
	@$(run_as_root) bash -euo pipefail -c '\
		if [ -f "$(ACME_HOME)/$(DOMAIN)_ecc/fullchain.cer" ]; then \
			rm -f "$(ACME_HOME)/$(DOMAIN)_ecc/fullchain.pem"; \
			cp "$(ACME_HOME)/$(DOMAIN)_ecc/fullchain.cer" "$(ACME_HOME)/$(DOMAIN)_ecc/fullchain.pem"; \
		fi; \
		{ \
			echo "export SSL_KEY_ECC=\"$(ACME_HOME)/$(DOMAIN)_ecc/$(DOMAIN).key\""; \
			echo "export SSL_CERT_ECC=\"$(ACME_HOME)/$(DOMAIN)_ecc/$(DOMAIN).cer\""; \
			echo "export SSL_CA_ECC=\"$(ACME_HOME)/$(DOMAIN)_ecc/ca.cer\""; \
			echo "export SSL_FULLCHAIN_ECC=\"$(ACME_HOME)/$(DOMAIN)_ecc/fullchain.pem\""; \
		} > /etc/homelab/acme-env.sh; \
		systemctl start acme-renewal.service 2>/dev/null || true; \
		echo "🔄 ACME renewal step completed"; \
	'

# ============================================================================
# 4. ACME Migration (dangerous, one-time)
# ============================================================================
# This target:
#   - requires MIGRATE=1
#   - migrates legacy /root/.acme.sh state
#   - fixes permissions
#   - clears canonical TLS store
#   - forces full certificate redeploy
#
# MUST NOT be used during normal operation.
# ============================================================================

.PHONY: acme-migrate-and-deploy
acme-migrate-and-deploy:
	@$(run_as_root) bash -euo pipefail -c '\
		if [ "$${MIGRATE:-0}" != "1" ]; then \
			echo "❌ MIGRATE=1 required"; exit 1; \
		fi; \
		if [ ! -d "/root/.acme.sh/bardi.ch_ecc" ]; then \
			echo "❌ No legacy ACME state"; exit 1; \
		fi; \
		if [ -d "$(ACME_HOME)/bardi.ch_ecc" ]; then \
			echo "❌ ACME_HOME already migrated"; exit 1; \
		fi; \
		echo "🚚 Migrating legacy ACME state"; \
		cp -rf /root/.acme.sh/* "$(ACME_HOME)"; \
		$(call acme_fix_perms,$(ACME_HOME)); \
		echo "🧹 Clearing canonical TLS store"; \
		rm -rf /var/lib/ssl/canonical/*; \
		echo "🚀 Forcing full certificate redeploy"; \
		"$(CERTS_DEPLOY)" renew; \
		"$(CERTS_DEPLOY)" prepare; \
		"$(CERTS_DEPLOY)" deploy dnsdist; \
		echo "🟢 Migration complete"; \
	'


# ============================================================================
# 5. Systemd Reload Helper
# ============================================================================
.PHONY: systemd-reload
systemd-reload:
	@$(run_as_root) systemctl daemon-reload
