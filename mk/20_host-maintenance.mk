###############################################################################
# Host maintenance
###############################################################################

.PHONY: update-os
.PHONY: update-ct220
.PHONY: update-ct225
.PHONY: update-linux-fleet

define update_ct
	@if ! $(run_as_root) pct status $(1) | grep -q '^status: running$$'; then \
		echo "⏭️  Skipping CT $(1) ($(2)): not running"; \
	else \
		echo "🚀 Updating CT $(1) ($(2))"; \
		$(run_as_root) pct exec $(1) -- apt update; \
		$(run_as_root) pct exec $(1) -- env DEBIAN_FRONTEND=noninteractive apt full-upgrade -y; \
		$(run_as_root) pct exec $(1) -- apt autoremove -y; \
		$(run_as_root) pct exec $(1) -- apt clean; \
	fi
endef

update-os:
	@echo "🚀 Updating OS packages"
	@$(run_as_root) apt update
	@$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt full-upgrade -y
	@$(run_as_root) apt autoremove -y
	@$(run_as_root) apt clean
	@if [ -f /var/run/reboot-required ]; then \
		echo "⚠️ Reboot required"; \
		echo "   Run: sudo reboot"; \
	else \
		echo "✅ No reboot required"; \
	fi

update-ct220:
	$(call update_ct,220,netbird-exit)

update-ct225:
	$(call update_ct,225,immich)

update-linux-fleet: \
	update-os \
	update-ct220 \
	update-ct225
	@echo "✅ Linux fleet updated"