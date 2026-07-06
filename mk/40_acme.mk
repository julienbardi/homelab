# mk/40_acme.mk
# ============================================================================
# ACME Certificate Lifecycle Management
#
# There are TWO distinct operations in this file:
#
#   1. acme-renew
#      - The ONLY correct way to renew certificates.
#      - Calls `acme.sh --cron` which performs:
#           * expiry checks
#           * challenge validation
#           * issuance
#           * deploy hooks
#      - Runs daily via systemd.
#
#   2. acme-migrate-and-deploy (formerly acme-renew-all)
#      - NOT a renewal mechanism.
#      - One-time migration tool for legacy ACME state.
#      - Copies old /root/.acme.sh state into /var/lib/acme.
#      - Re-applies permissions.
#      - Clears canonical TLS store.
#      - Forces full redeploy of certificates.
#      - MUST NOT be used during normal operation.
#
# These two targets MUST remain separate.
# There is NO duplication: they perform fundamentally different jobs.
# ============================================================================

ACME_BIN  := $(ACME_HOME)/acme.sh

# ----------------------------------------------------------------------------
# 1. Normal ACME Renewal (safe, idempotent, daily)
# ----------------------------------------------------------------------------
.PHONY: acme-renew
acme-renew: ddns-env acme-install acme-write-infomaniak-token acme-timer-install
	@$(run_as_root) bash -euo pipefail -c '\
		DIR="$(ACME_HOME)/$(DOMAIN)_ecc"; \
		if [ ! -d "$$DIR" ]; then \
			echo "❌ No ACME identity found for $$DIR."; \
			echo "   Run: make acme-issue first."; \
			exit 1; \
		fi; \
		\
		echo "🔄 Triggering ACME systemd timer (root-managed renewal)..."; \
		systemctl start acme-renewal.service; \
		\
		echo "⏳ Waiting 3 seconds for service to settle..."; \
		sleep 3; \
		\
		echo; echo "📋 Checking acme-renewal.service status:"; \
		systemctl --no-pager --full status acme-renewal.service || true; \
		\
		echo; echo "📜 Last 20 log lines:"; \
		journalctl -u acme-renewal.service -n 20 --no-pager || true; \
		\
		CERT="$${DIR}/fullchain.cer"; \
		if [ -f "$$CERT" ]; then \
			echo; echo "🔍 Certificate timestamps:"; \
			openssl x509 -in "$$CERT" -noout -dates || true; \
		else \
			echo; echo "❌ No certificate found at $$CERT"; \
		fi; \
	'

# ------------------------------------------------------------
# ACME Renewal Timer (Systemd) - CLEAN + IDEMPOTENT VERSION
# ------------------------------------------------------------

SERVICE_FILE := /etc/systemd/system/acme-renewal.service
TIMER_FILE   := /etc/systemd/system/acme-renewal.timer

define SERVICE_CONTENT
[Unit]
Description=Renew ACME Certificates
After=network-online.target

[Service]
Type=oneshot
Environment=SOPS_AGE_KEY_FILE=/etc/sops/keys/age.key
EnvironmentFile=/etc/homelab/ddns.env
ExecStart=$(ACME_BIN) --cron --home $(ACME_HOME)
User=root
Group=root
endef

define TIMER_CONTENT
[Unit]
Description=Daily ACME Certificate Renewal Check

[Timer]
OnCalendar=*-*-* 00:00:00
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
endef

export SERVICE_CONTENT
export TIMER_CONTENT

.PHONY: acme-timer-install
acme-timer-install:
	@$(run_as_root) env \
		SERVICE_CONTENT="$${SERVICE_CONTENT}" \
		TIMER_CONTENT="$${TIMER_CONTENT}" \
		bash -euo pipefail -c '\
			CHANGED=0; \
			\
			if [ "$$(printf "%s" "$$SERVICE_CONTENT")" != "$$(cat "$(SERVICE_FILE)" 2>/dev/null)" ]; then \
				echo "⏱️  Updating ACME service unit..."; \
				printf "%s" "$$SERVICE_CONTENT" | install -m 644 /dev/stdin "$(SERVICE_FILE)"; \
				CHANGED=1; \
			fi; \
			\
			if [ "$$(printf "%s" "$$TIMER_CONTENT")" != "$$(cat "$(TIMER_FILE)" 2>/dev/null)" ]; then \
				echo "⏱️  Updating ACME timer unit..."; \
				printf "%s" "$$TIMER_CONTENT" | install -m 644 /dev/stdin "$(TIMER_FILE)"; \
				CHANGED=1; \
			fi; \
			\
			if [ $$CHANGED -eq 1 ]; then \
				systemctl daemon-reload; \
				systemctl enable --now acme-renewal.timer; \
				echo "✅ ACME systemd timer updated and active."; \
			else \
				echo "ℹ️ ACME systemd timer is already up-to-date."; \
			fi \
	'


# ----------------------------------------------------------------------------
# 2. Migration + Forced Redeploy (dangerous, manual, one-time)
#
# This target is intentionally protected:
#   - Requires MIGRATE=1 to run.
#   - Aborts if no legacy state exists.
#   - Aborts if ACME_HOME already contains migrated state.
#
# This prevents accidental destructive use.
# ----------------------------------------------------------------------------
.PHONY: acme-migrate-and-deploy
acme-migrate-and-deploy:
	@$(run_as_root) bash -euo pipefail -c '\
		# Guards
		if [ "$${MIGRATE:-0}" != "1" ]; then \
			echo "❌ REFUSING: This is a destructive migration target."; \
			echo "   Use: make acme-migrate-and-deploy MIGRATE=1"; \
			exit 1; \
		fi; \
		\
		if [ ! -d "/root/.acme.sh/bardi.ch_ecc" ]; then \
			echo "❌ No legacy ACME state found in /root/.acme.sh — aborting."; \
			exit 1; \
		fi; \
		\
		if [ -d "$(ACME_HOME)/bardi.ch_ecc" ]; then \
			echo "❌ ACME_HOME already contains migrated state — aborting."; \
			exit 1; \
		fi; \
		\
		echo "🚚 Migrating legacy ACME state into $(ACME_HOME)..."; \
		cp -rf /root/.acme.sh/* "$(ACME_HOME)"; \
		\
		echo "🛡️ Fixing permissions..."; \
		$(call acme_fix_perms,$(ACME_HOME)); \
		\
		echo " Clearing canonical TLS store..."; \
		rm -rf /var/lib/ssl/canonical/*; \
		\
		echo "🚀 Forcing full certificate redeploy..."; \
		"$(REPO_ROOT)/scripts/deploy_certificates.sh" renew; \
		"$(REPO_ROOT)/scripts/deploy_certificates.sh" prepare; \
		"$(REPO_ROOT)/scripts/deploy_certificates.sh" deploy dnsdist; \
		\
		echo "✅ Migration + forced deploy complete."; \
	'

# ----------------------------------------------------------------------------
# 3. ACME Initial Issuance (safe, idempotent, systemd-managed)
# ----------------------------------------------------------------------------

.PHONY: acme-issue
acme-issue: install-all secrets-ready ddns-env acme-install acme-write-infomaniak-token acme-issue-service-install systemd-reload
	@$(run_as_root) systemctl start --no-block acme-issue.service
	@echo "🚀 ACME issuance triggered via systemd (non-blocking)."
	@echo "   Check progress with: sudo journalctl -u acme-issue.service -f"

.PHONY: acme-issue-service-install
acme-issue-service-install:
	@$(run_as_root) bash -euo pipefail -c '\
		SRC="$(REPO_ROOT)/config/systemd/acme-issue.service"; \
		DST="/etc/systemd/system/acme-issue.service"; \
		echo "⚙️  Installing acme-issue.service to $$DST"; \
		install -m 644 "$$SRC" "$$DST"; \
	'

.PHONY: systemd-reload
systemd-reload:
	@$(run_as_root) systemctl daemon-reload
