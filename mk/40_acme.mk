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

ACME_HOME := /var/lib/acme
ACME_BIN  := $(ACME_HOME)/acme.sh

# ----------------------------------------------------------------------------
# 1. Normal ACME Renewal (safe, idempotent, daily)
# ----------------------------------------------------------------------------
.PHONY: acme-renew
acme-renew: | ensure-run-as-root acme-ensure-dirs acme-install
	@{ \
		echo "🔄 Running ACME renewal..."; \
		$(run_as_root) $(ACME_BIN) --cron --home "$(ACME_HOME)"; \
	}

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
acme-migrate-and-deploy: ensure-run-as-root
	@{ \
		# Guards
		[ "$(MIGRATE)" = "1" ] || { \
			echo "❌ REFUSING: This is a destructive migration target."; \
			echo "   Use: make acme-migrate-and-deploy MIGRATE=1"; \
			exit 1; \
		}; \
		[ -d "/root/.acme.sh/bardi.ch_ecc" ] || { \
			echo "❌ No legacy ACME state found in /root/.acme.sh — aborting."; \
			exit 1; \
		}; \
		[ ! -d "$(ACME_HOME)/bardi.ch_ecc" ] || { \
			echo "❌ ACME_HOME already contains migrated state — aborting."; \
			exit 1; \
		}; \
		\
		echo "🚚 Migrating legacy ACME state into $(ACME_HOME)..."; \
		$(run_as_root) cp -rf /root/.acme.sh/* "$(ACME_HOME)"; \
		\
		echo "🛡️ Fixing permissions..."; \
		$(call acme_fix_perms,$(ACME_HOME)); \
		\
		echo "🧹 Clearing canonical TLS store..."; \
		$(run_as_root) rm -rf /var/lib/ssl/canonical/*; \
		\
		echo "🚀 Forcing full certificate redeploy..."; \
		$(REPO_ROOT)/scripts/deploy_certificates.sh renew; \
		$(REPO_ROOT)/scripts/deploy_certificates.sh prepare; \
		$(REPO_ROOT)/scripts/deploy_certificates.sh deploy dnsdist; \
		\
		echo "✅ Migration + forced deploy complete."; \
	}

