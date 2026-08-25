# mk/router/20_network_dhcp_dns.mk
# ------------------------------------------------------------
# Router network stack (DHCP + dnsmasq):
#   - DHCP pool + static leases
#   - DHCP validation
#   - DHCP inspection helpers
#   - dnsmasq templating + sync
#   - dnsmasq invariants
# ------------------------------------------------------------

# Shell-only aggregator for dhcp_static_* variables (RAM-only, WITH_SECRETS-scoped)
DHCP_AGGREGATE = for v in $$(compgen -A variable | grep '^dhcp_static_'); do printf "%s " "$${!v}"; done

# ------------------------------------------------------------
# DHCP static lease validation
# ------------------------------------------------------------

.PHONY: router-dhcp-static-validate
router-dhcp-static-validate: secrets-ready
	@$(call WITH_SECRETS, bash -c '\
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
router-dhcp-range-ensure: secrets-ready | ensure-router-ula router-ssh-check
	@echo "🛡️ Enforcing DHCP pool range via NVRAM (no commit, no restart)"

	@ssh "$(SSH_HOST_ROUTER)" 'set -e; \
cur_start="$$(nvram get dhcp_start 2>/dev/null || echo)"; \
cur_end="$$(nvram get dhcp_end 2>/dev/null || echo)"; \
desired_start="$(DHCP_DYNAMIC_START)"; \
desired_end="$(DHCP_DYNAMIC_END)"; \
changed=0; \
\
if [ "$$cur_start" != "$$desired_start" ]; then \
	echo "🔧 dhcp_start ➡️ $$desired_start"; \
	nvram set dhcp_start="$$desired_start"; \
	changed=1; \
fi; \
\
if [ "$$cur_end" != "$$desired_end" ]; then \
	echo "🔧 dhcp_end ➡️ $$desired_end"; \
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
router-dhcp-static-ensure: router-dhcp-static-validate secrets-ready | ensure-router-ula router-ssh-check
	@echo "🛡️ Enforcing DHCP static leases via NVRAM (no commit, no restart)"

	@$(call WITH_SECRETS, bash -c '\
		desired="$$( $(DHCP_AGGREGATE) )"; \
		if [ -z "$$desired" ]; then \
			echo "⚠️ STATIC_DHCP is empty — skipping enforcement"; \
			exit 0; \
		fi; \
		ssh "$(SSH_HOST_ROUTER)" \
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

.PHONY: router-dnsmasq-sync
router-dnsmasq-sync: | $(HOMELAB_ENV_DST) $(INSTALL_FILES_IF_CHANGED) router-bootstrap-primitives router-ssh-check
	@echo "📡 Templating and Syncing DNS configuration for $(DOMAIN)..."

	@set -e; \
	sed "s|\$${NAS_LAN_IP}|$(NAS_LAN_IP)|g; s|\$${DOMAIN}|$(DOMAIN)|g" \
		"$(REPO_ROOT)/router/jffs/configs/dnsmasq.conf.add" \
		> "$(TMP_DNSMASQ_ADD)"; \
	\
	cp "$(REPO_ROOT)/router/jffs/configs/hosts.add" "$(TMP_DNSMASQ_HOSTS)"; \
	\
	DNS_CHANGED=0; export DNS_CHANGED; \
	VERBOSE=1 $(INSTALL_FILES_IF_CHANGED) DNS_CHANGED \
		"" "" "$(TMP_DNSMASQ_ADD)" "$(ROUTER_ADDR)" "$(ROUTER_SSH_PORT)" "/jffs/configs/dnsmasq.conf.add" \
		"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0644" \
		"" "" "$(TMP_DNSMASQ_HOSTS)" "$(ROUTER_ADDR)" "$(ROUTER_SSH_PORT)" "/jffs/configs/hosts.add" \
		"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0644" \
		|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; \
	\
	if [ "$$DNS_CHANGED" -eq 1 ]; then \
		echo "🔄 DNS configuration changed (pending restart)"; \
		ssh "$(SSH_HOST_ROUTER)" "touch /jffs/homelab_dnsmasq_changed"; \
	else \
		echo "✅ DNS configuration up-to-date (no restart needed)"; \
	fi


# ------------------------------------------------------------
# dnsmasq.conf.add deploy (files only, marks dirty on change)
# ------------------------------------------------------------

ROUTER_DNSMASQ_CONF := /jffs/configs/dnsmasq.conf.add
LOCAL_DNSMASQ_CONF  := $(REPO_ROOT)/router/jffs/configs/dnsmasq.conf.add

.PHONY: router-dnsmasq-conf
router-dnsmasq-conf: secrets-ready ensure-host-default-route router-bootstrap-primitives ensure-router-ula router-ssh-check
	@echo "🔧 Installing dnsmasq.conf.add (no restart)"
	@set -e; \
	env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(INSTALL_FILE_IF_CHANGED) \
			"" "" "$(LOCAL_DNSMASQ_CONF)" \
			"$(ROUTER_ADDR)" "$(ROUTER_SSH_PORT)" "$(ROUTER_DNSMASQ_CONF)" \
			"0" "0" "0644"; \
	RC=$$?; \
	if [ $$RC -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		echo "🔄 dnsmasq.conf.add changed (pending restart)"; \
		ssh "$(SSH_HOST_ROUTER)" "touch /jffs/homelab_dnsmasq_changed"; \
	elif [ $$RC -eq 0 ]; then \
		echo "✅ dnsmasq.conf.add up-to-date"; \
	else \
		exit 1; \
	fi

	@echo "🔍 Checking if dnsmasq restart is required"
	@ssh "$(SSH_HOST_ROUTER)" '\
		touch /jffs/dnsmasq-config.ready; \
		if [ -f /jffs/homelab_dnsmasq_changed ]; then \
			echo "🔄 dnsmasq config changed — restarting dnsmasq"; \
			rm -f /jffs/homelab_dnsmasq_changed; \
			killall dnsmasq 2>/dev/null; \
			/usr/sbin/dnsmasq --log-async; \
			echo "🟢 dnsmasq restarted cleanly"; \
		else \
			echo "✅ dnsmasq config unchanged — no restart needed"; \
		fi \
	'

# ------------------------------------------------------------
# DHCP inspection helpers
# ------------------------------------------------------------

.PHONY: router-dhcp-list
router-dhcp-list: secrets-ready router-ssh-check
	@echo "📋 Listing current DHCP clients on router:"
	@$(call WITH_SECRETS, sh -c '\
		ssh "$(SSH_HOST_ROUTER)" "set -e; \
			if [ -f /var/lib/misc/dnsmasq.leases ]; then \
				cat /var/lib/misc/dnsmasq.leases; \
			else \
				echo \"⚠️ dnsmasq.leases not found\"; \
			fi"; \
	')

.PHONY: router-dhcp-list-static-format
router-dhcp-list-static-format: secrets-ready router-ssh-check
	@echo "📋 DHCP clients in static NVRAM format:"
	@$(call WITH_SECRETS, sh -c '\
		ssh "$(SSH_HOST_ROUTER)" "\
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

# ------------------------------------------------------------
# dnsmasq invariants
# ------------------------------------------------------------

.PHONY: router-dnsmasq-invariants
router-dnsmasq-invariants: router-ssh-check
	@echo "🛡️ Validating dnsmasq invariants on router"
	@ssh "$(SSH_HOST_ROUTER)" '\
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
