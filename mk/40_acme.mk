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
	@echo "🔍 Validating ACME configuration"; \
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
	echo "🟢 ACME paths validated (Make + shell)"

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

.PHONY: acme-bootstrap
acme-bootstrap: acme-validate-paths
	@$(run_as_root) bash -euo pipefail -c '\
		echo "🔧 Installing ACME scripts"; \
		install -m 0755 "$(REPO_ROOT)/scripts/acme-issue.sh" "$(ACME_ISSUE_SCRIPT)"; \
		install -m 0755 "$(REPO_ROOT)/scripts/acme-renew.sh" "$(ACME_RENEW_SCRIPT)"; \
		\
		echo "🔧 Rendering ACME systemd units"; \
		envsubst < "$(REPO_ROOT)/config/systemd/acme-issue.service.in" > "$(ACME_ISSUE_SERVICE)"; \
		envsubst < "$(REPO_ROOT)/config/systemd/acme-issue.timer.in"   > "$(ACME_ISSUE_TIMER)"; \
		envsubst < "$(REPO_ROOT)/config/systemd/acme-renew.service.in" > "$(ACME_RENEW_SERVICE)"; \
		envsubst < "$(REPO_ROOT)/config/systemd/acme-renew.timer.in"   > "$(ACME_RENEW_TIMER)"; \
		chmod 0644 "$(ACME_ISSUE_SERVICE)" "$(ACME_ISSUE_TIMER)" "$(ACME_RENEW_SERVICE)" "$(ACME_RENEW_TIMER)"; \
		\
		echo "🔄 Reloading systemd"; \
		systemctl daemon-reload; \
		systemctl enable --now acme-renew.timer; \
		echo "🟢 ACME bootstrap complete"; \
	'

# ============================================================================
# ACME Script Validation
# ============================================================================
.PHONY: acme-validate-scripts
acme-validate-scripts:
	@echo "🔍 Validating ACME scripts"; \
	for f in "$(ACME_ISSUE_SCRIPT)" "$(ACME_RENEW_SCRIPT)"; do \
		if [ ! -f "$$f" ]; then \
			echo "❌ Missing ACME script: $$f"; exit 1; \
		fi; \
		if [ ! -x "$$f" ]; then \
			echo "❌ ACME script not executable: $$f"; exit 1; \
		fi; \
	done; \
	echo "🟢 ACME scripts validated"

# ============================================================================
# ACME Systemd Unit Validation
# ============================================================================
.PHONY: acme-validate-units
acme-validate-units:
	@echo "🔍 Validating ACME systemd units"; \
	for u in "$(ACME_ISSUE_SERVICE)" "$(ACME_ISSUE_TIMER)" "$(ACME_RENEW_SERVICE)" "$(ACME_RENEW_TIMER)"; do \
		if [ ! -f "$$u" ]; then \
			echo "❌ Missing ACME systemd unit: $$u"; exit 1; \
		fi; \
	done; \
	echo "🟢 ACME systemd units validated"

# ============================================================================
# ACME Systemd Syntax Validation
# ============================================================================
.PHONY: acme-validate-systemd
acme-validate-systemd:
	@echo "🔍 Validating systemd syntax"; \
	systemctl daemon-reload; \
	for u in acme-issue.service acme-renew.service acme-renew.timer; do \
		if ! systemctl status "$$u" >/dev/null 2>&1; then \
			echo "❌ systemd cannot load $$u"; exit 1; \
		fi; \
	done; \
	echo "🟢 systemd syntax validated"

# ============================================================================
# ACME Timer Validation
# ============================================================================
.PHONY: acme-validate-timer
acme-validate-timer:
	@echo "🔍 Validating ACME renewal timer"; \
	if ! systemctl is-enabled acme-renew.timer >/dev/null 2>&1; then \
		echo "❌ acme-renew.timer is not enabled"; exit 1; \
	fi; \
	echo "🟢 ACME renewal timer validated"

# ============================================================================
# ACME_HOME Validation
# ============================================================================
.PHONY: acme-validate-home
acme-validate-home:
	@echo "🔍 Validating ACME_HOME"; \
	if [ ! -d "$(ACME_HOME)" ]; then \
		echo "❌ ACME_HOME missing: $(ACME_HOME)"; exit 1; \
	fi; \
	if [ ! -f "$(ACME_HOME)/acme.sh" ]; then \
		echo "❌ acme.sh missing in ACME_HOME"; exit 1; \
	fi; \
	echo "🟢 ACME_HOME validated"

# ============================================================================
# Infomaniak Token Validation
# ============================================================================
.PHONY: acme-validate-token
acme-validate-token:
	@echo "🔍 Validating Infomaniak token"; \
	if [ ! -f "$(ACME_HOME)/infomaniak_token" ]; then \
		echo "❌ Infomaniak token missing"; exit 1; \
	fi; \
	if ! grep -q . "$(ACME_HOME)/infomaniak_token"; then \
		echo "❌ Infomaniak token empty"; exit 1; \
	fi; \
	echo "🟢 Infomaniak token validated"

# ============================================================================
# Issuance Directory Validation
# ============================================================================
.PHONY: acme-validate-issuance
acme-validate-issuance:
	@echo "🔍 Validating ACME issuance directory"; \
	if [ ! -d "$(ACME_HOME)/$(DOMAIN)_ecc" ]; then \
		echo "❌ No issuance directory for $(DOMAIN)"; exit 1; \
	fi; \
	echo "🟢 ACME issuance directory validated"

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
	@echo "🟢 ACME subsystem converged"

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
			echo "🟢 ACME certificate already exists"; \
		fi; \
		if [ -f "$(ACME_HOME)/$(DOMAIN)_ecc/fullchain.cer" ]; then \
			rm -f "$(ACME_HOME)/$(DOMAIN)_ecc/fullchain.pem"; \
			cp "$(ACME_HOME)/$(DOMAIN)_ecc/fullchain.cer" "$(ACME_HOME)/$(DOMAIN)_ecc/fullchain.pem"; \
			echo "🟢 Updated fullchain.pem from fullchain.cer"; \
		fi; \
		{ \
			echo "export SSL_KEY_ECC=\"$(ACME_HOME)/$(DOMAIN)_ecc/$(DOMAIN).key\""; \
			echo "export SSL_CERT_ECC=\"$(ACME_HOME)/$(DOMAIN)_ecc/$(DOMAIN).cer\""; \
			echo "export SSL_CA_ECC=\"$(ACME_HOME)/$(DOMAIN)_ecc/ca.cer\""; \
			echo "export SSL_FULLCHAIN_ECC=\"$(ACME_HOME)/$(DOMAIN)_ecc/fullchain.pem\""; \
		} > /etc/homelab/acme-env.sh; \
	'
	@echo "SSL_KEY_ECC=$(ACME_HOME)/$(DOMAIN)_ecc/$(DOMAIN).key" >> $(abspath .state/EXPORT.env 2>/dev/null || echo /dev/null)
	@echo "SSL_CERT_ECC=$(ACME_HOME)/$(DOMAIN)_ecc/$(DOMAIN).cer" >> $(abspath .state/EXPORT.env 2>/dev/null || echo /dev/null)
	@echo "SSL_CA_ECC=$(ACME_HOME)/$(DOMAIN)_ecc/ca.cer" >> $(abspath .state/EXPORT.env 2>/dev/null || echo /dev/null)
	@echo "SSL_FULLCHAIN_ECC=$(ACME_HOME)/$(DOMAIN)_ecc/fullchain.pem" >> $(abspath .state/EXPORT.env 2>/dev/null || echo /dev/null)

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
