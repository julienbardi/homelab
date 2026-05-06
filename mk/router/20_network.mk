# mk/router/20_network.mk
# ------------------------------------------------------------
# Router network stack:
#   - dnsmasq templating + sync
#   - IPv6 ULA / NVRAM provisioning
#   - DHCP pool + static leases
#   - DDNS deploy + execution
#   - DHCP inspection helpers
# ------------------------------------------------------------


# Shell-only aggregator for dhcp_static_* variables (RAM-only, WITH_SECRETS-scoped)
DHCP_AGGREGATE = for v in $$(compgen -A variable | grep '^dhcp_static_'); do printf "%s " "$${!v}"; done

# ------------------------------------------------------------
# DHCP static lease validation
# ------------------------------------------------------------

.PHONY: router-dhcp-static-validate
router-dhcp-static-validate: secrets-ready
	@echo "🔍 Validating STATIC_DHCP entries"
	@$(WITH_SECRETS) \
		entries="$$( $(DHCP_AGGREGATE) )"; \
		if [ -z "$$entries" ]; then \
			echo "⚠️ STATIC_DHCP is empty — nothing to validate"; \
			exit 0; \
		fi; \
		ips=$$(printf "%s\n" $$entries | tr ' ' '\n' | awk -F'=' '{print $$2}'); \
		if echo "$$ips" | grep -Eq '\.1$$'; then \
			echo "❌ ERROR: STATIC_DHCP contains forbidden IP ending in .1"; \
			echo "$$ips" | grep '\.1$$'; \
			exit 1; \
		fi; \
		if echo "$$ips" | awk -F. '$$4 > $(DHCP_STATIC_MAX) {print}' | grep -q .; then \
			echo "❌ ERROR: STATIC_DHCP contains IPs >= .$$(($(DHCP_STATIC_MAX)+1)) (reserved for dynamic pool)"; \
			echo "$$ips" | awk -F. '$$4 > $(DHCP_STATIC_MAX)'; \
			exit 1; \
		fi; \
		dups=$$(printf "%s\n" $$ips | sort | uniq -d); \
		if [ -n "$$dups" ]; then \
			echo "❌ ERROR: Duplicate IPs detected in STATIC_DHCP"; \
			echo "$$dups"; \
			exit 1; \
		fi; \
		macs=$$(printf "%s\n" $$entries | tr ' ' '\n' | awk -F'=' '{print $$1}'); \
		mac_dups=$$(printf "%s\n" $$macs | sort | uniq -d); \
		if [ -n "$$mac_dups" ]; then \
			echo "❌ ERROR: Duplicate MAC addresses detected in STATIC_DHCP"; \
			echo "$$mac_dups"; \
			exit 1; \
		fi; \
		echo "🟢 STATIC_DHCP validation passed"

# ------------------------------------------------------------
# DHCP pool range (dynamic leases)
# ------------------------------------------------------------

.PHONY: router-dhcp-range-ensure
router-dhcp-range-ensure: secrets-ready | ensure-router-ula
	@echo "🛡️ Enforcing DHCP pool range via NVRAM"
	@$(WITH_SECRETS) \
		router_ssh="ssh -p $$router_ssh_port $$router_user@$$router_addr"; \
		$$router_ssh 'set -e; \
			current_start="$$(nvram get dhcp_start || true)"; \
			current_end="$$(nvram get dhcp_end || true)"; \
			desired_start="$(DHCP_DYNAMIC_START)"; \
			desired_end="$(DHCP_DYNAMIC_END)"; \
			changed=0; \
			if [ "$$current_start" != "$$desired_start" ]; then \
				echo "🔧 Updating dhcp_start → $$desired_start"; \
				nvram set dhcp_start="$$desired_start"; \
				changed=1; \
			fi; \
			if [ "$$current_end" != "$$desired_end" ]; then \
				echo "🔧 Updating dhcp_end → $$desired_end"; \
				nvram set dhcp_end="$$desired_end"; \
				changed=1; \
			fi; \
			if [ "$$changed" -eq 1 ]; then \
				nvram commit; \
				sleep 1;
				echo "🔄 Restarting dnsmasq"; \
				if command -v service >/dev/null 2>&1 && service restart_dnsmasq >/dev/null 2>&1; then \
					true; \
				else \
					killall -HUP dnsmasq 2>/dev/null || /etc/init.d/dnsmasq restart 2>/dev/null || true; \
				fi; \
				echo "✅ DHCP pool updated"; \
			else \
				echo "ℹ️ DHCP pool already converged"; \
			fi'

# ------------------------------------------------------------
# DHCP static leases
# ------------------------------------------------------------

.PHONY: router-dhcp-static-ensure
router-dhcp-static-ensure: router-dhcp-static-validate secrets-ready | ensure-router-ula
	@echo "🛡️ Enforcing DHCP static leases via NVRAM"
	@$(WITH_SECRETS) \
		router_ssh="ssh -p $$router_ssh_port $$router_user@$$router_addr"; \
		desired="$$( $(DHCP_AGGREGATE) )"; \
		if [ -z "$$desired" ]; then \
			echo "⚠️ STATIC_DHCP is empty — skipping enforcement"; \
			exit 0; \
		fi; \
		$$router_ssh 'set -e; \
			current="$$(nvram get dhcp_staticlist || true)"; \
			desired="'"$$desired"'"; \
			if [ -z "$$desired" ]; then \
				echo "⚠️ STATIC_DHCP is empty — skipping enforcement"; \
				exit 0; \
			fi; \
			if [ "$$current" != "$$desired" ]; then \
				echo "🔧 Updating dhcp_staticlist"; \
				nvram set dhcp_staticlist="$$desired"; \
				nvram commit; \
				if command -v service >/dev/null 2>&1 && service restart_dnsmasq >/dev/null 2>&1; then \
					true; \
				else \
					killall -HUP dnsmasq 2>/dev/null || /etc/init.d/dnsmasq restart 2>/dev/null || true; \
				fi; \
				echo "✅ DHCP static leases updated"; \
			else \
				echo "ℹ️ DHCP static leases already converged"; \
			fi'

# ------------------------------------------------------------
# dnsmasq templating + sync
# ------------------------------------------------------------

.PHONY: router-dnsmasq-sync
router-dnsmasq-sync: secrets-ready | $(INSTALL_FILES_IF_CHANGED) ensure-router-ula
	@echo "📡 Templating and Syncing DNS configuration for $(DOMAIN)..."
	@mkdir -p .tmp
	@$(WITH_SECRETS) \
		sed "s|\$${NAS_LAN_IP}|$$nas_lan_ip|g; s|\$${DOMAIN}|$(DOMAIN)|g" \
			$(REPO_ROOT)/router/jffs/configs/dnsmasq.conf.add > .tmp/dnsmasq.conf.add
	@DNS_CHANGED=0; export DNS_CHANGED; \
	$(WITH_SECRETS) \
		VERBOSE=1 $(INSTALL_FILES_IF_CHANGED) DNS_CHANGED \
			"" "" ".tmp/dnsmasq.conf.add" "$$router_addr" "$$router_ssh_port" "/jffs/configs/dnsmasq.conf.add" \
			"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0644" \
			"" "" "$(REPO_ROOT)/router/jffs/configs/hosts.add" "$$router_addr" "$$router_ssh_port" "/jffs/configs/hosts.add" \
			"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0644" \
		|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; \
		if [ "$$DNS_CHANGED" -eq 1 ]; then \
			echo "🔄 DNS changed. Restarting service..."; \
			router_ssh="ssh -p $$router_ssh_port $$router_user@$$router_addr"; \
			$$router_ssh 'if command -v service >/dev/null 2>&1 && service restart_dnsmasq >/dev/null 2>&1; then echo restarted; else killall -HUP dnsmasq 2>/dev/null || /etc/init.d/dnsmasq restart 2>/dev/null || true; fi'; \
			echo "✅ DNS configuration synced"; \
		fi

# ------------------------------------------------------------
# IPv6 ULA / NVRAM provisioning
# ------------------------------------------------------------

.PHONY: router-provision-nvram
router-provision-nvram: secrets-ready | ensure-router-ula
	@echo "🛡️ Syncing Router NVRAM (ULA/RDNSS) using SSOT"
	@$(WITH_SECRETS) \
		ULA_PREFIX_NVRAM="$$( \
			if [ -z "$$nas_lan_ip6" ]; then \
				echo ""; \
			else \
				echo "$$nas_lan_ip6" | sed -n 's/::[0-9a-fA-F]*$$/::\/48/p'; \
			fi \
		)"; \
		if [ -n "$$nas_lan_ip6" ] && [ -z "$$ULA_PREFIX_NVRAM" ]; then \
			echo "❌ Could not compute ULA_PREFIX_NVRAM from NAS_LAN_IP6=$$nas_lan_ip6"; \
			exit 1; \
		fi; \
		echo "🔧 Using ULA_PREFIX_NVRAM='$$ULA_PREFIX_NVRAM'"; \
		router_ssh="ssh -p $$router_ssh_port $$router_user@$$router_addr"; \
		$$router_ssh 'set -e; \
			if [ "$$(nvram get ipv6_ula_prefix)" != "'"$$ULA_PREFIX_NVRAM"'" ] || \
				 [ "$$(nvram get ipv6_dns1)" != "$$router_ula_ip6" ]; then \
				echo "⚙️ Updating NVRAM values..."; \
				nvram set ipv6_ula_enable=1; \
				nvram set ipv6_ula_prefix="'"$$ULA_PREFIX_NVRAM"'"; \
				nvram set ipv6_dns1=$$router_ula_ip6; \
				nvram set ipv6_dns61_x=$$router_ula_ip6; \
				nvram commit || { echo "❌ nvram commit failed"; exit 1; }; \
				echo "✅ NVRAM updated."; \
			else \
				echo "✅ NVRAM already converged."; \
			fi'

# ------------------------------------------------------------
# DDNS deploy + execution
# ------------------------------------------------------------

.PHONY: router-ddns
router-ddns: ddns-conf-generate ensure-router-ula
	@$(WITH_SECRETS) \
		echo "📡 Deploying DDNS configuration to router"; \
		env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
			$(INSTALL_FILE_IF_CHANGED) \
				"" "" "$(TMP_DDNS_CONF)" \
				"$$router_addr" "$$router_ssh_port" "/jffs/scripts/.ddns_confidential" \
				"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0600" \
			|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]
	@echo "🔄 Executing DDNS update"
	@router_ssh="ssh -p $$router_ssh_port $$router_user@$$router_addr"; \
	$$router_ssh '$(ROUTER_SCRIPTS)/ddns-start'
	@[ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ] && echo "🧹 Cleaning up local DDNS secrets"
	rm -f "$(TMP_DDNS_CONF)"
	@echo "✅ DDNS update complete"

# ------------------------------------------------------------
# DHCP inspection helpers
# ------------------------------------------------------------

.PHONY: router-dhcp-list
router-dhcp-list:
	@echo "📋 Listing current DHCP clients on router:"
	@$(WITH_SECRETS) \
		router_ssh="ssh -p $$router_ssh_port $$router_user@$$router_addr"; \
		$$router_ssh 'set -e; \
			if [ -f /var/lib/misc/dnsmasq.leases ]; then \
				cat /var/lib/misc/dnsmasq.leases; \
			else \
				echo "⚠️ dnsmasq.leases not found"; \
			fi'

.PHONY: router-dhcp-list-static-format
router-dhcp-list-static-format:
	@echo "📋 DHCP clients in static NVRAM format:"
	@$(WITH_SECRETS) \
		router_ssh="ssh -p $$router_ssh_port $$router_user@$$router_addr"; \
		$$router_ssh 'set -e; \
			if [ -f /var/lib/misc/dnsmasq.leases ]; then \
				awk "{print \$$2 \"=\" \$$3 \"=\" \$$4 \"=0\"}" /var/lib/misc/dnsmasq.leases; \
			else \
				echo "⚠️ dnsmasq.leases not found"; \
			fi'
