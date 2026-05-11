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

	@ssh -p "$(ROUTER_SSH_PORT)" \
		"$(ROUTER_USER)@$(ROUTER_ADDR)" \
		'set -e; \
			cur_start="$$(nvram get dhcp_start 2>/dev/null || echo)"; \
			cur_end="$$(nvram get dhcp_end 2>/dev/null || echo)"; \
			desired_start="$(DHCP_DYNAMIC_START)"; \
			desired_end="$(DHCP_DYNAMIC_END)"; \
			changed=0; \
			\
			if [ "$$cur_start" != "$$desired_start" ]; then \
				echo "🔧 dhcp_start → $$desired_start"; \
				nvram set dhcp_start="$$desired_start"; \
				changed=1; \
			fi; \
			\
			if [ "$$cur_end" != "$$desired_end" ]; then \
				echo "🔧 dhcp_end → $$desired_end"; \
				nvram set dhcp_end="$$desired_end"; \
				changed=1; \
			fi; \
			\
			if [ "$$changed" -eq 1 ]; then \
				nvram commit; \
				echo "🔄 Restarting dnsmasq"; \
				if command -v service >/dev/null 2>&1 && service restart_dnsmasq >/dev/null 2>&1; then \
					true; \
				else \
					killall -HUP dnsmasq 2>/dev/null || /etc/init.d/dnsmasq restart 2>/dev/null || true; \
				fi; \
				echo "🟢 DHCP pool updated"; \
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
		desired="$$( $(DHCP_AGGREGATE) )"; \
		if [ -z "$$desired" ]; then \
			echo "⚠️ STATIC_DHCP is empty — skipping enforcement"; \
			exit 0; \
		fi; \
		ssh -p "$$ROUTER_SSH_PORT" \
			"$$ROUTER_USER@$$ROUTER_ADDR" \
			'set -e; \
				current="$$(nvram get dhcp_staticlist 2>/dev/null || echo)"; \
				desired="'"$$desired"'"; \
				if [ -z "$$desired" ]; then \
					echo "⚠️ STATIC_DHCP is empty — skipping enforcement"; \
					exit 0; \
				fi; \
				if [ "$$current" != "$$desired" ]; then \
					echo "🔧 Updating dhcp_staticlist"; \
					nvram set dhcp_staticlist="$$desired"; \
					nvram commit; \
					echo "🔄 Restarting dnsmasq"; \
					if command -v service >/dev/null 2>&1 && service restart_dnsmasq >/dev/null 2>&1; then \
						true; \
					else \
						killall -HUP dnsmasq 2>/dev/null || /etc/init.d/dnsmasq restart 2>/dev/null || true; \
					fi; \
					echo "🟢 DHCP static leases updated"; \
				else \
					echo "ℹ️ DHCP static leases already converged"; \
				fi'


# ------------------------------------------------------------
# dnsmasq templating + sync
# ------------------------------------------------------------

router-dnsmasq-sync: | $(HOMELAB_ENV_DST) $(INSTALL_FILES_IF_CHANGED) router-bootstrap-run-as-root ensure-router-ula
	@echo "📡 Templating and Syncing DNS configuration for $(DOMAIN)..."

	$(call TMPFILE_BLOCK,"$(TMP_DNSMASQ_ADD) $(TMP_DNSMASQ_HOSTS)", \
		sed "s|\$${NAS_LAN_IP}|$(NAS_LAN_IP)|g; s|\$${DOMAIN}|$(DOMAIN)|g" \
			"$(REPO_ROOT)/router/jffs/configs/dnsmasq.conf.add" \
			> "$(TMP_DNSMASQ_ADD)"; \

		cp "$(REPO_ROOT)/router/jffs/configs/hosts.add" "$(TMP_DNSMASQ_HOSTS)"; \

		DNS_CHANGED=0; export DNS_CHANGED; \
		VERBOSE=1 $(INSTALL_FILES_IF_CHANGED) DNS_CHANGED \
			"" "" "$(TMP_DNSMASQ_ADD)" "$(ROUTER_ADDR)" "$(ROUTER_SSH_PORT)" "/jffs/configs/dnsmasq.conf.add" \
			"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0644" \
			"" "" "$(TMP_DNSMASQ_HOSTS)" "$(ROUTER_ADDR)" "$(ROUTER_SSH_PORT)" "/jffs/configs/hosts.add" \
			"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0644" \
			|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; \

		if [ "$$DNS_CHANGED" -eq 1 ]; then \
			echo "🔄 DNS changed. Restarting service..."; \
			$(ROUTER_SSH) 'killall -HUP dnsmasq 2>/dev/null || true'; \
			echo "✅ DNS configuration synced"; \
		fi; \
	)


# ------------------------------------------------------------
# IPv6 ULA / NVRAM provisioning
# ------------------------------------------------------------

.PHONY: router-provision-nvram
router-provision-nvram: secrets-ready | ensure-router-ula
	@echo "🛡️ Syncing Router NVRAM (ULA/RDNSS) using SSOT"

	@# Compute ULA prefix (fail-fast if invalid)
	@ULA_PREFIX_NVRAM="$$( \
		if [ -n "$(NAS_LAN_IP6)" ]; then \
			printf "%s" "$(NAS_LAN_IP6)" | sed -n 's/::[0-9a-fA-F]*$$/::\/48/p'; \
		fi \
	)"; \
	if [ -z "$$ULA_PREFIX_NVRAM" ]; then \
		echo "❌ ULA prefix undefined — NAS_LAN_IP6 missing or invalid"; \
		exit 1; \
	fi

	@echo "🔧 Using ULA_PREFIX_NVRAM='$$ULA_PREFIX_NVRAM'"

	@ssh -p "$(ROUTER_SSH_PORT)" \
		"$(ROUTER_USER)@$(ROUTER_ADDR)" \
		'set -e; \
			cur_prefix="$$(nvram get ipv6_ula_prefix 2>/dev/null || echo)"; \
			cur_dns1="$$(nvram get ipv6_dns1 2>/dev/null || echo)"; \
			cur_dns61="$$(nvram get ipv6_dns61_x 2>/dev/null || echo)"; \
			changed=0; \
			\
			if [ "$$cur_prefix" != "'"$$ULA_PREFIX_NVRAM"'" ]; then \
				echo "🔧 ipv6_ula_prefix → '"$$ULA_PREFIX_NVRAM"'"; \
				nvram set ipv6_ula_prefix="'"$$ULA_PREFIX_NVRAM"'"; \
				nvram set ipv6_ula_enable=1; \
				changed=1; \
			fi; \
			\
			if [ "$$cur_dns1" != "$(ROUTER_ULA_IP6)" ]; then \
				echo "🔧 ipv6_dns1 → $(ROUTER_ULA_IP6)"; \
				nvram set ipv6_dns1="$(ROUTER_ULA_IP6)"; \
				changed=1; \
			fi; \
			\
			if [ "$$cur_dns61" != "$(ROUTER_ULA_IP6)" ]; then \
				echo "🔧 ipv6_dns61_x → $(ROUTER_ULA_IP6)"; \
				nvram set ipv6_dns61_x="$(ROUTER_ULA_IP6)"; \
				changed=1; \
			fi; \
			\
			if [ "$$changed" -eq 1 ]; then \
				nvram commit; \
				echo "🟢 NVRAM updated"; \
			else \
				echo "ℹ️ NVRAM already converged"; \
			fi'


# ------------------------------------------------------------
# DDNS deploy + execution
# ------------------------------------------------------------

.PHONY: router-ddns
router-ddns: ensure-router-ula
	@echo "📡 Deploying DDNS configuration to router"

	@# Generate DDNS confidential file inline (no separate target)
	@$(WITH_SECRETS) \
		umask 077; \
		printf "%s\n%s\n%s\n" \
			"DNS_TOPDOMAIN_NAME='$$ddns_topdomain'" \
			"DDNSUSERNAME='$$ddns_username'" \
			"DDNSPASSWORD='$$ddns_password'" \
			> "$(TMP_DDNS_CONF)"

	@# Push to router
	@$(WITH_SECRETS) \
		env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
			$(INSTALL_FILE_IF_CHANGED) \
				"" "" "$(TMP_DDNS_CONF)" \
				"$$ROUTER_ADDR" "$$ROUTER_SSH_PORT" "/jffs/scripts/.ddns_confidential" \
				"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0600" \
			|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]

	@echo "🔄 Executing DDNS update"
	@ssh -p "$(ROUTER_SSH_PORT)" "$(ROUTER_USER)@$(ROUTER_ADDR)" \
		'$(ROUTER_SCRIPTS)/ddns-start'

	@echo "🧹 Cleaning up RAM-only local DDNS secrets"
	@rm -f "$(TMP_DDNS_CONF)"

	@echo "🟢 DDNS update complete"

# ------------------------------------------------------------
# DHCP inspection helpers
# ------------------------------------------------------------

.PHONY: router-dhcp-list
router-dhcp-list:
	@echo "📋 Listing current DHCP clients on router:"
	@$(WITH_SECRETS) \
		router_ssh="ssh -p $$ROUTER_SSH_PORT $$ROUTER_USER@$$ROUTER_ADDR"; \
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
		router_ssh="ssh -p $$ROUTER_SSH_PORT $$ROUTER_USER@$$ROUTER_ADDR"; \
		$$router_ssh 'set -e; \
			if [ -f /var/lib/misc/dnsmasq.leases ]; then \
				awk "{print \$$2 \"=\" \$$3 \"=\" \$$4 \"=0\"}" /var/lib/misc/dnsmasq.leases; \
			else \
				echo "⚠️ dnsmasq.leases not found"; \
			fi'
