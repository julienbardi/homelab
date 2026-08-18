# --------------------------------------------------------------------
# mk/wireguard/30_generate.mk — WireGuard Config Generation
# --------------------------------------------------------------------

# export RUNTIME_DIR := $(STAMP_DIR_ROOT)/runtime

.PHONY: ensure-wg-key-dirs
ensure-wg-key-dirs:
	@[ -n "$(WG_ROOT)" ] || { \
		echo "ERROR: WG_ROOT is empty — contract violation"; \
		exit 1; \
	}
	@[ -d "$(WG_ROOT)" ] || { \
		echo "ERROR: WG_ROOT directory does not exist: $(WG_ROOT)"; \
		exit 1; \
	}
	@$(run_as_root) install -d -o $(ROOT_UID) -g $(ROOT_GID) -m 700 \
		$(WG_ROOT)/keys/servers \
		$(WG_ROOT)/keys/clients

wg-generate: ensure-state-dirs ensure-wg-key-dirs ensure-state-dirs $(WG_INTERFACE_LIST_STAMP) \
		wg-subnets router-bootstrap-wg-keys $(INSTALL_PATH)/wg-generate-configs.sh
	@ROUTER_OLD_HASH=$$(sha256sum $(WG_OUTPUT_ROUTER)/*.conf 2>/dev/null | sha256sum | awk '{print $$1}') || ROUTER_OLD_HASH=""; \
	$(run_as_root) env \
		RUNTIME_DIR="$(RUNTIME_DIR)" \
		DNS_TOPDOMAIN_NAME="$$( $(call WITH_SECRETS, sh -c 'echo "$$ddns_topdomain"') )" \
		NAS_LAN_IP="$(NAS_LAN_IP)" \
		NAS_LAN_IP6="$(NAS_LAN_IP6)" \
		LAN_ROUTER="$(LAN_ROUTER)" \
		WG_ROOT="$(WG_ROOT)" \
		USER_GID="$(USER_GID)" \
		ROUTER_WAN_IFACE="$(ROUTER_WAN_IFACE)" \
		INSTALL_FILE_IF_CHANGED="$(INSTALL_FILE_IF_CHANGED)" \
		LAN_NAS="$(LAN_NAS)" \
		LAN6_NAS="$(LAN6_NAS)" \
		WG_DOH_IPV4=$(WG_DOH_IPV4) \
		WG_DOH_IPV6=$(WG_DOH_IPV6) \
		WG_DNS_ROUTER_IPV4=$(WG_DNS_ROUTER_IPV4) \
		WG_DNS_NAS_IPV6=$(WG_DNS_NAS_IPV6) \
		LAN_NET=$(LAN_NET) \
		LAN6_NET=$(LAN6_NET) \
		ROUTER_IDENTITY=$(ROUTER_IDENTITY) \
		ROOT_UID=$(ROOT_UID) \
		$(INSTALL_PATH)/wg-generate-configs.sh; \
	ROUTER_NEW_HASH=$$(sha256sum $(WG_OUTPUT_ROUTER)/*.conf 2>/dev/null | sha256sum | awk '{print $$1}') || ROUTER_NEW_HASH=""; \
	if [ "$$ROUTER_OLD_HASH" != "$$ROUTER_NEW_HASH" ]; then \
		echo "🔄 WireGuard configuration mutation caught — marking runtime topologies dirty"; \
		$(run_as_root) touch "$(WG_ROUTER_DIRTY_STAMP)" "$(WG_NAS_DIRTY_STAMP)"; \
	fi

wg-clean-state:
	@$(WG_SUDO) rm -f "$(WG_SUBNETS_MK)" "$(WG_ROUTER_DIRTY_STAMP)" "$(WG_NAS_DIRTY_STAMP)"

$(WG_INTERFACES_MK): $(WG_INTERFACES_TSV)
	@echo "🔧 Writing WG interfaces mk file: $(WG_INTERFACES_MK)"
	@interfaces="$$(cut -f1 $(WG_INTERFACES_TSV) | tail -n +2)"; \
	echo "WG_INTERFACES := $$interfaces" | $(run_as_root) tee $(WG_INTERFACES_MK) >/dev/null; \
	$(run_as_root) chmod 0644 $(WG_INTERFACES_MK)
