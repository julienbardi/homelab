# mk/20_host-maintenance.mk
.PHONY: update-os
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