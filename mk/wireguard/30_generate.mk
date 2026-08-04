# --------------------------------------------------------------------
# mk/wireguard/30_generate.mk — WireGuard Config Generation
# --------------------------------------------------------------------

wg-generate: $(WG_INTERFACE_LIST_STAMP) \
		$(WG_SUBNETS_MK) router-bootstrap-wg-keys $(INSTALL_PATH)/wg-generate-configs.sh | $(run_as_root)
		@echo "🔍 Staging configuration hash states before generation execution"; \
		ROUTER_OLD_HASH=$$(sha256sum $(WG_OUTPUT_ROUTER)/*.conf 2>/dev/null | sha256sum | awk '{print $$1}') || ROUTER_OLD_HASH=""; \
		DNS_TOPDOMAIN_NAME="$$( $(call WITH_SECRETS, sh -c 'echo "$$ddns_topdomain"') )" \
		NAS_LAN_IP="$(NAS_LAN_IP)" \
		NAS_LAN_IP6="$(NAS_LAN_IP6)" \
		LAN_ROUTER="$(LAN_ROUTER)" \
		WG_ROOT="$(WG_ROOT)" \
		USER_GID="$(USER_GID)" \
		ROUTER_LAN_IFACE="$(ROUTER_LAN_IFACE)" \
		$(INSTALL_PATH)/wg-generate-configs.sh; \
		ROUTER_NEW_HASH=$$(sha256sum $(WG_OUTPUT_ROUTER)/*.conf 2>/dev/null | sha256sum | awk '{print $$1}') || ROUTER_NEW_HASH=""; \
		if [ "$$ROUTER_OLD_HASH" != "$$ROUTER_NEW_HASH" ]; then \
				echo "⚠️  WireGuard configuration mutation caught — marking runtime topologies dirty"; \
				$(run_as_root) touch "$(WG_ROUTER_DIRTY_STAMP)" "$(WG_NAS_DIRTY_STAMP)"; \
		fi

wg-clean-state:
		@$(WG_SUDO) rm -f "$(WG_SUBNETS_MK)" "$(WG_ROUTER_DIRTY_STAMP)" "$(WG_NAS_DIRTY_STAMP)"

$(WG_INTERFACES_MK): enforce-wg-permissions $(WG_INTERFACES_TSV)
