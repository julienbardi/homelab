# --------------------------------------------------------------------
# mk/wireguard/60_lifecycle.mk — Unified WireGuard Lifecycle
# --------------------------------------------------------------------

wg-install: wg-install-router wg-install-nas

wg-up: wg-up-router wg-up-nas
		@echo "🚀 WireGuard fully converged"

wg-down: wg-down-router wg-down-nas
		@echo "✅ WireGuard fully stopped"

wg-restart: wg-down wg-up

wg-status: $(INSTALL_PATH)/wgctl.sh
		@$(WG_ENV) \
				ROUTER_CONTROL_PLANE=1 \
				$(INSTALL_PATH)/wgctl.sh router status || true; \
		$(WG_ENV) \
				NAS_CONTROL_PLANE=1 \
				$(INSTALL_PATH)/wgctl.sh nas status || true

wg-clean-out: wg-down-router wg-down-nas wg-clean-state
		@if [ "$(VERBOSE)" -ge 1 ]; then echo " Cleaning local scripts & SSH sockets"; fi
		@$(WG_SUDO) rm -f "$(INSTALL_PATH)/wgctl.sh" \
										"$(INSTALL_PATH)/wg-generate-configs.sh" \
										"$(INSTALL_PATH)/wg-readiness-probe.sh"
		@ssh -O exit "$(SSH_SOCK_FILE_ROUTER)" 2>/dev/null || true;
		@rm -f "$(SSH_SOCK_FILE_ROUTER)"
		@echo " Cleaning remote router scripts"
		@ssh "$(SSH_HOST_ROUTER)" "rm -f $(ROUTER_SCRIPTS)/wg-firewall.sh"
