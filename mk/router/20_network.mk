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
	@$(call WITH_SECRETS, sh -c '\
		entries="$$( $(DHCP_AGGREGATE) )"; \
		if [ -z "$$entries" ]; then \
			echo "⚠️ STATIC_DHCP is empty — nothing to validate"; \
			exit 0; \
		fi; \
		ips=$$(printf "%s\n" $$entries | tr " " "\n" | awk -F"=" "{print \$$2}"); \
		if echo "$$ips" | grep -Eq "\.1$$"; then \
			echo "❌ ERROR: STATIC_DHCP contains forbidden IP ending in .1"; \
			echo "$$ips" | grep "\.1$$"; \
			exit 1; \
		fi; \
		if echo "$$ips" | awk -F. "\$$4 > $(DHCP_STATIC_MAX) {print}" | grep -q .; then \
			echo "❌ ERROR: STATIC_DHCP contains IPs >= .$$(($(DHCP_STATIC_MAX)+1))"; \
			echo "$$ips" | awk -F. "\$$4 > $(DHCP_STATIC_MAX)"; \
			exit 1; \
		fi; \
		dups=$$(printf "%s\n" $$ips | sort | uniq -d); \
		if [ -n "$$dups" ]; then \
			echo "❌ ERROR: Duplicate IPs detected"; \
			echo "$$dups"; \
			exit 1; \
		fi; \
		macs=$$(printf "%s\n" $$entries | tr " " "\n" | awk -F"=" "{print \$$1}"); \
		mac_dups=$$(printf "%s\n" $$macs | sort | uniq -d); \
		if [ -n "$$mac_dups" ]; then \
			echo "❌ ERROR: Duplicate MACs detected"; \
			echo "$$mac_dups"; \
			exit 1; \
		fi; \
		echo "🟢 STATIC_DHCP validation passed"; \
	')


# ------------------------------------------------------------
# DHCP pool range (dynamic leases)
# ------------------------------------------------------------

.PHONY: router-dhcp-range-ensure
router-dhcp-range-ensure: secrets-ready | ensure-router-ula
	@echo "🛡️ Enforcing DHCP pool range via NVRAM"

	@ssh -p "$(ROUTER_SSH_PORT)" \
		"$(SSH_USER_ROUTER)@$(ROUTER_ADDR)" \
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

	@$(call WITH_SECRETS, sh -c '\
		desired="$$( $(DHCP_AGGREGATE) )"; \
		if [ -z "$$desired" ]; then \
			echo "⚠️ STATIC_DHCP is empty — skipping enforcement"; \
			exit 0; \
		fi; \
		ssh -p "$$ROUTER_SSH_PORT" "$$SSH_USER_ROUTER@$$ROUTER_ADDR" \
			"set -e; \
			current=\$$(nvram get dhcp_staticlist 2>/dev/null || echo); \
			desired=\"$$desired\"; \
			if [ \"\$$current\" != \"\$$desired\" ]; then \
				echo \"🔧 Updating dhcp_staticlist\"; \
				nvram set dhcp_staticlist=\"\$$desired\"; \
				nvram commit; \
				echo \"🔄 Restarting dnsmasq\"; \
				if command -v service >/dev/null 2>&1 && service restart_dnsmasq >/dev/null 2>&1; then \
					true; \
				else \
					killall -HUP dnsmasq 2>/dev/null || /etc/init.d/dnsmasq restart 2>/dev/null || true; \
				fi; \
				echo \"🟢 DHCP static leases updated\"; \
			else \
				echo \"ℹ️ DHCP static leases already converged\"; \
			fi" \
	')


# ------------------------------------------------------------
# dnsmasq templating + sync
# ------------------------------------------------------------

router-dnsmasq-sync: | $(HOMELAB_ENV_DST) $(INSTALL_FILES_IF_CHANGED) router-bootstrap-run-as-root ensure-router-ula router-ra-policy
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
# IPv6 ULA / NVRAM provisioning (static, deterministic)
# ------------------------------------------------------------

.PHONY: router-provision-nvram
router-provision-nvram: secrets-ready | ensure-router-ula
	@echo "🛡️ Syncing Router NVRAM (ULA only — DNS handled by dns-enforcer)"

	@# Compute ULA prefix (/48) from NAS_LAN_IP6 (fail-fast if invalid)
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
		"$(SSH_USER_ROUTER)@$(ROUTER_ADDR)" \
		'set -e; \
			cur_prefix="$$(nvram get ipv6_ula_prefix 2>/dev/null || echo)"; \
			cur_lan_addr="$$(nvram get ipv6_lan_addr 2>/dev/null || echo)"; \
			changed=0; \
			\
			# Enforce ULA prefix (/48)
			if [ "$$cur_prefix" != "'"$$ULA_PREFIX_NVRAM"'" ]; then \
				echo "🔧 ipv6_ula_prefix → '"$$ULA_PREFIX_NVRAM"'"; \
				nvram set ipv6_ula_prefix="'"$$ULA_PREFIX_NVRAM"'"; \
				nvram set ipv6_ula_enable=1; \
				changed=1; \
			fi; \
			\
			# Enforce router's own ULA LAN address (::1)
			if [ "$$cur_lan_addr" != "$(ROUTER_ULA_IP6)" ]; then \
				echo "🔧 ipv6_lan_addr → $(ROUTER_ULA_IP6)"; \
				nvram set ipv6_lan_addr="$(ROUTER_ULA_IP6)"; \
				nvram set ipv6_lan_prefix="48"; \
				changed=1; \
			fi; \
			\
			# IMPORTANT: Do NOT set ipv6_dns1 here.
			# DNS advertisement is dynamic and handled by dns-enforcer.sh.
			\
			if [ "$$changed" -eq 1 ]; then \
				nvram commit; \
				echo "🟢 NVRAM updated"; \
			else \
				echo "ℹ️ NVRAM already converged"; \
			fi'

.PHONY: router-ra-policy
router-ra-policy: router-bootstrap-run-as-root
	@echo "🛡️ Enforcing router RA policy (disable default route in RA)"
	@ssh -p "$(ROUTER_SSH_PORT)" "$(SSH_USER_ROUTER)@$(ROUTER_ADDR)" 'set -e; \
		cur="$$(nvram get ipv6_accept_ra || echo unset)"; \
		if [ "$$cur" != "0" ]; then \
			echo "🔧 ipv6_accept_ra → 0"; \
			nvram set ipv6_accept_ra=0; \
			nvram commit; \
			echo "🔄 Restarting radvd"; \
			service restart_radvd; \
		else \
			echo "✔️ RA policy already enforced (ipv6_accept_ra=0)"; \
		fi'

# ------------------------------------------------------------
# DDNS deploy + execution
# ------------------------------------------------------------

.PHONY: router-ddns
router-ddns: ensure-router-ula
	@echo "📡 Deploying DDNS configuration to router"

	@# Generate DDNS confidential file inline (no separate target)
	@$(call WITH_SECRETS, sh -c '\
		umask 077; \
		printf "%s\n%s\n%s\n" \
			"DNS_TOPDOMAIN_NAME='\$$ddns_topdomain'" \
			"DDNSUSERNAME='\$$ddns_username'" \
			"DDNSPASSWORD='\$$ddns_password'" \
			> "$(TMP_DDNS_CONF)"; \
	')

	@# Push to router
	@$(call WITH_SECRETS, sh -c '\
		env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
			$(INSTALL_FILE_IF_CHANGED) \
				"" "" "$(TMP_DDNS_CONF)" \
				"$$ROUTER_ADDR" "$$ROUTER_SSH_PORT" "/jffs/scripts/.ddns_confidential" \
				"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0600" \
			|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; \
	')

	@echo "🔄 Executing DDNS update"
	@ssh -p "$(ROUTER_SSH_PORT)" "$(SSH_USER_ROUTER)@$(ROUTER_ADDR)" \
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
	@$(call WITH_SECRETS, sh -c '\
		router_ssh="ssh -p $$ROUTER_SSH_PORT $$SSH_USER_ROUTER@$$ROUTER_ADDR"; \
		$$router_ssh "set -e; \
			if [ -f /var/lib/misc/dnsmasq.leases ]; then \
				cat /var/lib/misc/dnsmasq.leases; \
			else \
				echo \"⚠️ dnsmasq.leases not found\"; \
			fi"; \
	')

.PHONY: router-dhcp-list-static-format
router-dhcp-list-static-format:
	@echo "📋 DHCP clients in static NVRAM format:"
	@$(call WITH_SECRETS, sh -c '\
		ssh -p $$ROUTER_SSH_PORT $$SSH_USER_ROUTER@$$ROUTER_ADDR "\
			set -e; \
			if [ ! -f /var/lib/misc/dnsmasq.leases ]; then \
				echo \"⚠️ dnsmasq.leases not found\"; \
				exit 0; \
			fi; \
			while read -r expiry mac ip host rest; do \
				[ \"\$$expiry\" = \"duid\" ] && continue; \
				[ -z \"\$$mac\" ] && continue; \
				echo \"\$$mac=\$$ip=\$$host=0\"; \
			done < /var/lib/misc/dnsmasq.leases \
		" \
	')


# router-ssh-invariants:
# Enforces LAN-only SSH by setting:
#   ssh_wan=0  → disable SSH on WAN
#   ssh_lan=1  → enable SSH on LAN
# AsusWRT defaults to WAN-enabled SSH when ssh_wan is unset.
# This target makes the invariant explicit and idempotent.
.PHONY: router-ssh-invariants
router-ssh-invariants:
	@echo "🛡️ Enforcing router SSH invariants (LAN-only SSH)"
	@ssh -p "$(ROUTER_SSH_PORT)" "$(SSH_USER_ROUTER)@$(ROUTER_ADDR)" 'set -e; \
		changed=0; \
		cur_wan="$$(nvram get ssh_wan || echo unset)"; \
		cur_lan="$$(nvram get ssh_lan || echo unset)"; \
		if [ "$$cur_wan" != "0" ]; then \
			echo "🔒 Disabling WAN SSH (ssh_wan=0)"; \
			nvram set ssh_wan=0; \
			changed=1; \
		fi; \
		if [ "$$cur_lan" != "1" ]; then \
			echo "🔓 Enabling LAN SSH (ssh_lan=1)"; \
			nvram set ssh_lan=1; \
			changed=1; \
		fi; \
		if [ "$$changed" -eq 1 ]; then \
			echo "💾 Committing NVRAM changes"; \
			nvram commit; \
			echo "🔁 Restarting SSH service"; \
			service restart_ssh; \
			echo "✅ SSH invariants enforced"; \
		else \
			echo "✔️ SSH invariants already satisfied"; \
		fi'

.PHONY: router-lan-domain
router-lan-domain: | router-ssh-check
	@LAN_DOMAIN="$$( $(call WITH_SECRETS, sh -c 'echo "$$ddns_topdomain"' ) )"; \
	ssh -p "$(ROUTER_SSH_PORT)" "$(SSH_USER_ROUTER)@$(ROUTER_ADDR)" '\
		cur="$$(nvram get lan_domain 2>/dev/null || true)"; \
		if [ "$$cur" = "'"$$LAN_DOMAIN"'" ]; then \
			echo "🌐 LAN domain already set to '"$$LAN_DOMAIN"'"; \
			exit 0; \
		fi; \
		nvram set lan_domain="'"$$LAN_DOMAIN"'"; \
		nvram commit; \
		service restart_dnsmasq; \
		echo "🌐 LAN domain set to '"$$LAN_DOMAIN"'"; \
	'

router-dhcp-static-export-secrets:
	@$(call WITH_SECRETS_v2, \
		tmp=$$(mktemp); \
		trap "rm -f $$tmp" EXIT INT TERM; \
		ssh -p "$$ROUTER_SSH_PORT" "$$SSH_USER_ROUTER@$$ROUTER_ADDR" \
			"nvram get dhcp_staticlist 2>/dev/null || true" \
			> "$$tmp"; \
		printf "DHCP static leases (paste into secrets.enc.yaml):\n\n"; \
		tr " " "\n" < "$$tmp" \
		| sed -n "s/^<\\([^>]*\\)>\\([^>]*\\)>>\$$/\\1=\\2==0/p" \
		| nl -w1 -s" " \
		| awk "{printf \"dhcp_static_%d=\\\"%s\\\"\\n\", $$1, $$2}"; \
		printf "\nDone\n"; \
	)

# Deploy dnsmasq.conf.add using IFC v2 (constant‑driven, contract‑correct)

ROUTER_DNSMASQ_CONF := /jffs/configs/dnsmasq.conf.add
LOCAL_DNSMASQ_CONF  := $(REPO_ROOT)/router/jffs/configs/dnsmasq.conf.add

.PHONY: router-dnsmasq-conf
router-dnsmasq-conf: secrets-ready ensure-default-gateway router-bootstrap-run-as-root ensure-router-ula router-lan-domain router-ra-policy
	@echo "🔧 Installing dnsmasq.conf.add..."
	@set -e; \
	env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(INSTALL_FILE_IF_CHANGED) \
			"" "" "$(LOCAL_DNSMASQ_CONF)" \
			"$(ROUTER_ADDR)" "$(ROUTER_SSH_PORT)" "$(ROUTER_DNSMASQ_CONF)" \
			"0" "0" "0644"; \
	RC=$$?; \
	if [ $$RC -eq 1 ] || [ $$RC -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		echo "🔄 dnsmasq.conf.add changed → restarting dnsmasq + radvd"; \
		$(ROUTER_SSH) "service restart_dnsmasq; service restart_radvd"; \
	else \
		echo "✔️ dnsmasq.conf.add up-to-date"; \
	fi
# ------------------------------------------------------------
# Router LAN IPv6 convergence (ULA + PD prefix)
# ------------------------------------------------------------

.PHONY: router-lan-ipv6
router-lan-ipv6: ensure-router-ula
	@echo "🛡️ [router-lan-ipv6] START"
	@echo "🛡️ Enforcing router LAN IPv6 (ULA + PD prefix)"
	@ssh -p "$(ROUTER_SSH_PORT)" "$(SSH_USER_ROUTER)@$(ROUTER_ADDR)" 'set -e; \
		# Derive current PD prefix from WAN GUA on eth0 \
		WAN="$$(ip -6 addr show dev eth0 | awk "/scope global/ && !/deprecated/ {print \$$2; exit}")"; \
		if [ -z "$$WAN" ]; then \
			echo "❌ No global IPv6 on eth0 — cannot derive PD prefix"; \
			exit 1; \
		fi; \
		# Strip /length \
		BASE="$$(printf "%s" "$$WAN" | cut -d/ -f1)"; \
		# Remove last hextet (BusyBox‑safe) \
		PD_RAW="$$(printf "%s" "$$BASE" | sed "s/:[0-9a-fA-F]\{1,4\}\$$/:/")"; \
		# Normalize any accidental ':::' → '::' \
		PD="$$(printf "%s" "$$PD_RAW" | sed "s/:::/::/")"; \
		echo "ℹ️ WAN GUA: $$WAN"; \
		echo "ℹ️ Derived PD prefix: $$PD"; \
		# Update NVRAM PD prefix to match reality \
		cur_pd="$$(nvram get ipv6_prefix || echo)"; \
		if [ "$$cur_pd" != "$$PD" ]; then \
			echo "🔧 ipv6_prefix → $$PD"; \
			nvram set ipv6_prefix="$$PD"; \
			nvram set ipv6_prefix_length=64; \
			nvram commit; \
		else \
			echo "ℹ️ ipv6_prefix already $$PD"; \
		fi; \
		# Remove existing global addresses on br0 \
		ip -6 addr show dev br0 | awk "/scope global/ {print \$$2}" | \
			while read p; do \
				echo "🔧 Removing old prefix $$p from br0"; \
				ip -6 addr del $$p dev br0 || true; \
			done; \
		# Add ULA (::1) \
		echo "🔧 Adding ULA fd89:7a3b:42c0::1/64 to br0"; \
		ip -6 addr add fd89:7a3b:42c0::1/64 dev br0 || true; \
		# Add PD prefix (::1) \
		echo "🔧 Adding PD $${PD}1/64 to br0"; \
		ip -6 addr add "$${PD}1/64" dev br0 || true; \
	'
