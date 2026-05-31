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
# DHCP pool range (dynamic leases) — pure NVRAM setter
# ------------------------------------------------------------

.PHONY: router-dhcp-range-ensure
router-dhcp-range-ensure: secrets-ready | ensure-router-ula
	@echo "🛡️ Enforcing DHCP pool range via NVRAM (no commit, no restart)"

	@ssh $(SSH_HOST_ROUTER) 'set -e; \
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
	echo "🟢 DHCP pool NVRAM updated (pending commit)"; \
	touch /jffs/homelab_nvram_dirty; \
else \
	echo "ℹ️ DHCP pool already converged"; \
fi'

# ------------------------------------------------------------
# DHCP static leases — pure NVRAM setter
# ------------------------------------------------------------

.PHONY: router-dhcp-static-ensure
router-dhcp-static-ensure: router-dhcp-static-validate secrets-ready | ensure-router-ula
	@echo "🛡️ Enforcing DHCP static leases via NVRAM (no commit, no restart)"

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
				echo \"🟢 DHCP static leases NVRAM updated (pending commit)\"; \
				touch /jffs/homelab_nvram_dirty; \
			else \
				echo \"ℹ️ DHCP static leases already converged\"; \
			fi" \
	')


# ------------------------------------------------------------
# dnsmasq templating + sync (files only, no restart)
# ------------------------------------------------------------

router-dnsmasq-sync: | $(HOMELAB_ENV_DST) $(INSTALL_FILES_IF_CHANGED) router-bootstrap-primitives
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
			echo "🔄 DNS configuration changed (pending restart)"; \
			ssh $(SSH_HOST_ROUTER) "touch /jffs/homelab_dnsmasq_changed"; \
		else \
			echo "✔️ DNS configuration up-to-date (no restart needed)"; \
		fi; \
	)


# ------------------------------------------------------------
# IPv6 ULA / NVRAM provisioning (static, deterministic) — pure setter
# ------------------------------------------------------------

.PHONY: router-provision-nvram
router-provision-nvram: secrets-ready | ensure-router-ula
	@echo "🛡️ Syncing Router NVRAM (ULA only — DNS handled by dns-enforcer) (no commit)"

	@ULA_PREFIX_NVRAM="$(ULA_PREFIX_NVRAM)"; \
	ROUTER_ULA_IP6="$(ROUTER_ULA_IP6)"; \
	ssh $(SSH_HOST_ROUTER) 'set -e; \
		cur_prefix=$$(nvram get ipv6_ula_prefix 2>/dev/null || echo); \
		cur_lan_addr=$$(nvram get ipv6_lan_addr 2>/dev/null || echo); \
		changed=0; \
		\
		echo "🔧 Using ULA_PREFIX_NVRAM='\$$ULA_PREFIX_NVRAM' (router ULA \$$ROUTER_ULA_IP6)"; \
		\
		if [ "$$cur_prefix" != "$$ULA_PREFIX_NVRAM" ]; then \
			echo "🔧 ipv6_ula_prefix → $$ULA_PREFIX_NVRAM"; \
			nvram set ipv6_ula_prefix="$$ULA_PREFIX_NVRAM"; \
			nvram set ipv6_ula_enable=1; \
			changed=1; \
		fi; \
		\
		if [ "$$cur_lan_addr" != "$$ROUTER_ULA_IP6" ]; then \
			echo "🔧 ipv6_lan_addr → $$ROUTER_ULA_IP6"; \
			nvram set ipv6_lan_addr="$$ROUTER_ULA_IP6"; \
			nvram set ipv6_lan_prefix=48; \
			changed=1; \
		fi; \
		\
		if [ "$$changed" -eq 1 ]; then \
			echo "🟢 ULA NVRAM updated (pending commit)"; \
			touch /jffs/homelab_nvram_dirty; \
		else \
			echo "ℹ️ ULA NVRAM already converged"; \
		fi'


.PHONY: router-ra-policy
router-ra-policy: router-bootstrap-primitives
	@echo "🛡️ Enforcing router RA policy (enable default route in RA) (no commit, no restart)"
	@ssh $(SSH_HOST_ROUTER) 'set -e; \
cur="$$(nvram get ipv6_accept_ra || echo unset)"; \
if [ "$$cur" != "2" ]; then \
	echo "🔧 ipv6_accept_ra → 2"; \
	nvram set ipv6_accept_ra=2; \
	echo "🟢 RA policy NVRAM updated (pending commit)"; \
	touch /jffs/homelab_nvram_dirty; \
else \
	echo "✔️ RA policy already enforced (ipv6_accept_ra=2)"; \
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
	@ssh $(SSH_HOST_ROUTER) '$(ROUTER_SCRIPTS)/ddns-start'

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
		router_ssh="ssh $$SSH_HOST_ROUTER"; \
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
		ssh $$SSH_HOST_ROUTER "\
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
	@ssh $(SSH_HOST_ROUTER) 'set -e; \
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


# ------------------------------------------------------------
# LAN domain — pure NVRAM setter
# ------------------------------------------------------------

.PHONY: router-lan-domain
router-lan-domain: | router-ssh-check
	@LAN_DOMAIN="$$( $(call WITH_SECRETS, sh -c 'echo "$$lan_domain"' ) )"; \
	ssh $(SSH_HOST_ROUTER) '\
		cur="$$(nvram get lan_domain 2>/dev/null || true)"; \
		if [ "$$cur" = "'"$$LAN_DOMAIN"'" ]; then \
			echo "🌐 LAN domain already set to '"$$LAN_DOMAIN"' (no commit, no restart)"; \
			exit 0; \
		fi; \
		nvram set lan_domain="'"$$LAN_DOMAIN"'"; \
		echo "🌐 LAN domain NVRAM updated to '"$$LAN_DOMAIN"' (pending commit)"; \
		touch /jffs/homelab_nvram_dirty; \
	'


router-dhcp-static-export-secrets:
	@$(call WITH_SECRETS_v2, \
		tmp=$$(mktemp); \
		trap "rm -f $$tmp" EXIT INT TERM; \
		ssh "$$SSH_HOST_ROUTER" \
			"nvram get dhcp_staticlist 2>/dev/null || true" \
			> "$$tmp"; \
		printf "DHCP static leases (paste into secrets.enc.yaml):\n\n"; \
		tr " " "\n" < "$$tmp" \
		| sed -n "s/^<\\([^>]*\\)>\\([^>]*\\)>>\$$/\\1=\\2==0/p" \
		| nl -w1 -s" " \
		| awk "{printf \"dhcp_static_%d=\\\"%s\\\"\\n\", $$1, $$2}"; \
		printf "\nDone\n"; \
	)


# ------------------------------------------------------------
# dnsmasq.conf.add deploy (files only, marks dirty on change)
# ------------------------------------------------------------

ROUTER_DNSMASQ_CONF := /jffs/configs/dnsmasq.conf.add
LOCAL_DNSMASQ_CONF  := $(REPO_ROOT)/router/jffs/configs/dnsmasq.conf.add

.PHONY: router-dnsmasq-conf
router-dnsmasq-conf: secrets-ready ensure-default-gateway router-bootstrap-primitives ensure-router-ula router-lan-domain router-ra-policy
	@echo "🔧 Installing dnsmasq.conf.add (no restart)"
	@set -e; \
	env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(INSTALL_FILE_IF_CHANGED) \
			"" "" "$(LOCAL_DNSMASQ_CONF)" \
			"$(ROUTER_ADDR)" "$(ROUTER_SSH_PORT)" "$(ROUTER_DNSMASQ_CONF)" \
			"0" "0" "0644"; \
	RC=$$?; \
	if [ $$RC -eq 1 ] || [ $$RC -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		echo "🔄 dnsmasq.conf.add changed (pending restart)"; \
		ssh $(SSH_HOST_ROUTER) "touch /jffs/homelab_dnsmasq_changed"; \
	else \
		echo "✔️ dnsmasq.conf.add up-to-date"; \
	fi

	@echo "🔍 Checking if dnsmasq restart is required"
	@ssh $(SSH_HOST_ROUTER) '\
		if [ -f /jffs/homelab_nvram_dirty ] || [ -f /jffs/homelab_dnsmasq_changed ]; then \
			echo "🔄 dnsmasq config changed — restarting dnsmasq"; \
			rm -f /jffs/homelab_nvram_dirty /jffs/homelab_dnsmasq_changed; \
			killall -HUP dnsmasq 2>/dev/null || service restart_dnsmasq; \
			echo "🟢 dnsmasq restarted"; \
		else \
			echo "✔️ dnsmasq config unchanged — no restart needed"; \
		fi \
	'




# ------------------------------------------------------------
# Unified NVRAM + dnsmasq/radvd converge (dirty-flag based)
# ------------------------------------------------------------

.PHONY: router-nvram-converge
router-nvram-converge: \
	router-dhcp-range-ensure \
	router-dhcp-static-ensure \
	router-lan-domain \
	router-provision-nvram \
	router-ra-policy \
	router-dnsmasq-sync \
	router-dnsmasq-conf
	@echo "🛡️ Committing NVRAM and restarting services (minimal restarts)"
	@ssh $(SSH_HOST_ROUTER) '\
		set -e; \
		RESTART=0; \
		\
		# NVRAM commit if dirty
		if [ -f /jffs/homelab_nvram_dirty ]; then \
			echo "💾 NVRAM dirty → committing"; \
			nvram commit; \
			rm -f /jffs/homelab_nvram_dirty; \
			RESTART=1; \
		fi; \
		\
		# dnsmasq-sync changed files?
		if [ -f /jffs/homelab_dnsmasq_changed ]; then \
			echo "🔄 dnsmasq-sync changed files"; \
			rm -f /jffs/homelab_dnsmasq_changed; \
			RESTART=1; \
		fi; \
		\
		if [ "$$RESTART" -eq 1 ]; then \
			echo "🔄 restart dnsmasq"; \
			service restart_dnsmasq; \
			echo "🔄 restart radvd"; \
			service restart_radvd || true; \
		else \
			echo "✔️ No changes → no restarts"; \
		fi; \
		echo "🟢 router-nvram-converge complete"; \
	'

.PHONY: router-ipv6-converge
router-ipv6-converge: router-nvram-converge router-dhcp6c-hook-converge
	@echo "🛡️ IPv6 converge: ensuring PD hook + dnsmasq RA"
	@ssh $(SSH_HOST_ROUTER) '\
		echo "🔄 Forcing DHCPv6-PD refresh"; \
		service start_dhcp6c || true; \
	'

.PHONY: router-dhcp6c-hook-converge
router-dhcp6c-hook-converge:
	@echo "🛡️ Ensuring dhcp6c-state hook exists"
	@ssh $(SSH_HOST_ROUTER) 'set -e; \
		mkdir -p /jffs/scripts; \
		tmp="/tmp/dhcp6c-state.$$"; \
		umask 077; \
		printf "%s\n" \
"#\!/bin/sh" \
"# DHCPv6-PD hook — restart dnsmasq so RA stays consistent" \
"service restart_dnsmasq" > "$$tmp"; \
mv "$$tmp" /jffs/scripts/dhcp6c-state; \
chmod 755 /jffs/scripts/dhcp6c-state; \
'

.PHONY: router-dnsmasq-invariants
router-dnsmasq-invariants:
	@echo "🛡️ Validating dnsmasq invariants on router"
	@ssh $(SSH_HOST_ROUTER) '\
		set -e; \
		echo "🔍 Checking dnsmasq process"; \
		pidof dnsmasq >/dev/null || { echo "❌ dnsmasq not running"; exit 1; }; \
		\
		echo "🔍 Checking dnsmasq is serving local domain"; \
		nslookup router.lan.bardi.ch 127.0.0.1 >/dev/null 2>&1 || { \
			echo "❌ dnsmasq not serving LAN domain"; exit 1; }; \
		\
		echo "🔍 Checking upstream resolvers"; \
		grep -q "server=$(NAS_LAN_IP)#15335" /jffs/configs/dnsmasq.conf.add || { \
			echo "❌ Missing IPv4 upstream to Unbound"; exit 1; }; \
		grep -q "server=$(ROUTER_ULA_IP6)#15335" /jffs/configs/dnsmasq.conf.add || { \
			echo "❌ Missing IPv6 upstream to Unbound"; exit 1; }; \
		\
		echo "🔍 Checking dnsmasq is reachable on LAN"; \
		nc -z -u 10.89.12.1 53 || { echo "❌ dnsmasq UDP/53 unreachable"; exit 1; }; \
		nc -z    10.89.12.1 53 || { echo "❌ dnsmasq TCP/53 unreachable"; exit 1; }; \
		\
		echo "🔍 Checking firewall allows router-local DNS"; \
		iptables -L HOMELAB_INPUT -n | grep -q "udp dpt:53" || { \
			echo "❌ Missing UDP/53 ACCEPT in HOMELAB_INPUT"; exit 1; }; \
		iptables -L HOMELAB_INPUT -n | grep -q "tcp dpt:53" || { \
			echo "❌ Missing TCP/53 ACCEPT in HOMELAB_INPUT"; exit 1; }; \
		\
		echo "🔍 Checking dnsmasq RA policy (ULA-only)"; \
		if grep -q "constructor:br0" /jffs/configs/dnsmasq.conf.add; then \
			echo "❌ Illegal RA constructor detected (global prefix leakage risk)"; \
			exit 1; \
		fi; \
		\
		echo "🟢 dnsmasq invariants satisfied"; \
	'
