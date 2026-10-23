# ============================================================================
# mk/05_bootstrap_time.mk
# Time / Timezone Bootstrap
# ============================================================================

TIMEZONE ?= Europe/Zurich

.PHONY: time-bootstrap
time-bootstrap:
	@set -euo pipefail; \
	CURRENT_TZ="$$(timedatectl show --property=Timezone --value)"; \
	if [ "$$CURRENT_TZ" != "$(TIMEZONE)" ]; then \
		echo "📝 Setting timezone to $(TIMEZONE)"; \
		$(run_as_root) timedatectl set-timezone "$(TIMEZONE)"; \
	else \
		echo "🟢 Timezone already $(TIMEZONE)"; \
	fi; \
	if ! timedatectl show --property=NTP --value | grep -qx yes; then \
		echo "📝 Enabling NTP"; \
		$(run_as_root) timedatectl set-ntp true; \
	else \
		echo "🟢 NTP already enabled"; \
	fi

.PHONY: time-status
time-status:
	@timedatectl