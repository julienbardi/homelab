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
	@$(call WITH_SECRETS, LC_CTYPE=en_US.UTF-8 bash -c '\
		entries="$$( $(DHCP_AGGREGATE) )"; \
		if [ -z "$$entries" ]; then \
			echo "⚠️ STATIC_DHCP is empty — nothing to validate"; \
			exit 0; \
		fi; \
		ips=$$(printf "%s\n" $$entries | tr " " "\n" | awk -F"=" "{print \$$2}"); \
		if echo "$$ips" | grep -Eq "\.1$$"; then \
			echo "❌ STATIC_DHCP contains forbidden IP ending in .1"; \
			echo "$$ips" | grep "\.1$$"; \
			exit 1; \
		fi; \
		if echo "$$ips" | awk -F. "\$$4 > $(DHCP_STATIC_MAX) {print}" | grep -q .; then \
			echo "❌ STATIC_DHCP contains IPs >= .$$(($(DHCP_STATIC_MAX)+1))"; \
			echo "$$ips" | awk -F. "\$$4 > $(DHCP_STATIC_MAX)"; \
			exit 1; \
		fi; \
		dups=$$(printf "%s\n" $$ips | sort | uniq -d); \
		if [ -n "$$dups" ]; then \
			echo "❌ Duplicate IPs detected"; \
			echo "$$dups"; \
			exit 1; \
		fi; \
		macs=$$(printf "%s\n" $$entries | tr " " "\n" | awk -F"=" "{print \$$1}"); \
		mac_dups=$$(printf "%s\n" $$macs | sort | uniq -d); \
		if [ -n "$$mac_dups" ]; then \
			echo "❌ Duplicate MACs detected"; \
			echo "$$mac_dups"; \
			exit 1; \
		fi; \
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🟢 STATIC_DHCP validation passed"; fi; \
	')

# ------------------------------------------------------------
# DHCP pool range (dynamic leases) — pure NVRAM setter
# ------------------------------------------------------------

.PHONY: router-dhcp-range-ensure
router-dhcp-range-ensure: secrets-ready | ensure-router-ula router-ssh-check
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🛡️ Enforcing DHCP pool range via NVRAM (no commit, no restart)"; fi; \
	ssh "$(SSH_HOST_ROUTER)" 'set -e; \
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
	if [ "$(VERBOSE)" -ge 1 ]; then echo "ℹ️ DHCP pool already converged"; fi; \
fi'

# ------------------------------------------------------------
# DHCP static leases — pure NVRAM setter
# ------------------------------------------------------------

.PHONY: router-dhcp-static-ensure
router-dhcp-static-ensure: router-dhcp-static-validate secrets-ready | ensure-router-ula router-ssh-check
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🛡️ Enforcing DHCP static leases via NVRAM (no commit, no restart)"; fi; \
	$(call WITH_SECRETS, LC_CTYPE=en_US.UTF-8 bash -c '\
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
				if [ "$(VERBOSE)" -ge 1 ]; then echo \"ℹ️ DHCP static leases already converged\"; fi; \
			fi" \
	')

# ------------------------------------------------------------
# DNS & DHCP Sovereign Infrastructure Synchronization & Validation
# ------------------------------------------------------------

.PHONY: router-dnsmasq-sync
router-dnsmasq-sync: | $(HOMELAB_ENV_DST) $(INSTALL_FILES_IF_CHANGED) router-bootstrap-primitives router-ssh-check
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "📡 Syncing sovereign DNS and network configuration files..."; fi; \
	set -e; \
	DNS_CHANGED=0; export DNS_CHANGED; \
	VERBOSE=1 $(INSTALL_FILES_IF_CHANGED) DNS_CHANGED \
		"" "" "$(REPO_ROOT)/router/jffs/configs/dnsmasq.conf.add" \
			"$(ROUTER_ADDR)" "$(ROUTER_SSH_PORT)" "/jffs/configs/dnsmasq.conf.add" \
			"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0644" \
		"" "" "$(REPO_ROOT)/router/jffs/configs/hosts.add" \
			"$(ROUTER_ADDR)" "$(ROUTER_SSH_PORT)" "/jffs/configs/hosts.add" \
			"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0644" \
		"" "" "$(REPO_ROOT)/router/jffs/configs/profile.add" \
			"$(ROUTER_ADDR)" "$(ROUTER_SSH_PORT)" "/jffs/profile.add" \
			"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0644" \
		|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; \
	\
	if [ "$$DNS_CHANGED" -eq 1 ]; then \
		echo "🔄 DNS configuration changes detected (pending test and restart)"; \
		ssh "$(SSH_HOST_ROUTER)" "touch /jffs/homelab_dnsmasq_changed"; \
	else \
		if [ "$(VERBOSE)" -ge 1 ]; then echo "✅ DNS configuration files up-to-date"; fi;\
	fi

.PHONY: router-dnsmasq-validate
router-dnsmasq-validate: router-dnsmasq-sync
	@echo "🔍 Validating remote dnsmasq.conf.add against config.mk specifications..."
	@printf '%s\n' \
		'CONF="/jffs/configs/dnsmasq.conf.add"' \
		'fail() { echo "❌ dnsmasq.conf.add drift: $$1"; exit 1; }' \
		'[ -f "$$CONF" ] || fail "configuration file not found"' \
		'check_line_exact() { grep -Fqx "$$1" "$$CONF" || fail "$$2"; }' \
		'check_line_exact "domain=$(LAN_DOMAIN)" "domain mismatch"' \
		'check_line_exact "local=/$(LAN_DOMAIN)/" "local zone mismatch"' \
		'check_line_exact "expand-hosts" "expand-hosts missing"' \
		'check_line_exact "localise-queries" "localise-queries missing"' \
		'check_line_exact "address=/router.$(LAN_DOMAIN)/$(LAN_ROUTER)" "router IPv4 address mismatch"' \
		'check_line_exact "address=/router.$(LAN_DOMAIN)/$(LAN6_ROUTER)" "router IPv6 address mismatch"' \
		'check_line_exact "ptr-record=$(LAN_ROUTER),router.$(LAN_DOMAIN)" "router IPv4 PTR mismatch"' \
		'check_line_exact "ptr-record=$(LAN6_ROUTER),router.$(LAN_DOMAIN)" "router IPv6 PTR mismatch"' \
		'check_line_exact "address=/diskstation.$(LAN_DOMAIN)/$(LAN_SYNOLOGY)" "diskstation IPv4 mismatch"' \
		'check_line_exact "address=/diskstation.$(LAN_DOMAIN)/$(LAN6_SYNOLOGY)" "diskstation IPv6 mismatch"' \
		'check_line_exact "ptr-record=$(LAN_SYNOLOGY),diskstation.$(LAN_DOMAIN)" "diskstation IPv4 PTR mismatch"' \
		'check_line_exact "ptr-record=$(LAN6_SYNOLOGY),diskstation.$(LAN_DOMAIN)" "diskstation IPv6 PTR mismatch"' \
		'check_line_exact "address=/qnap.$(LAN_DOMAIN)/$(LAN_QNAP)" "qnap IPv4 mismatch"' \
		'check_line_exact "address=/qnap.$(LAN_DOMAIN)/$(LAN6_QNAP)" "qnap IPv6 mismatch"' \
		'check_line_exact "ptr-record=$(LAN_QNAP),qnap.$(LAN_DOMAIN)" "qnap IPv4 PTR mismatch"' \
		'check_line_exact "ptr-record=$(LAN6_QNAP),qnap.$(LAN_DOMAIN)" "qnap IPv6 PTR mismatch"' \
		'check_line_exact "address=/pve.$(LAN_DOMAIN)/$(LAN_NAS)" "pve IPv4 mismatch"' \
		'check_line_exact "address=/pve.$(LAN_DOMAIN)/$(LAN6_NAS)" "pve IPv6 mismatch"' \
		'check_line_exact "ptr-record=$(LAN_NAS),pve.$(LAN_DOMAIN)" "pve IPv4 PTR mismatch"' \
		'check_line_exact "ptr-record=$(LAN6_NAS),pve.$(LAN_DOMAIN)" "pve IPv6 PTR mismatch"' \
		'check_line_exact "address=/raspberrypi.$(LAN_DOMAIN)/$(LAN_RASPBERRYPI)" "raspberrypi IPv4 mismatch"' \
		'check_line_exact "address=/raspberrypi.$(LAN_DOMAIN)/$(LAN6_RASPBERRYPI)" "raspberrypi IPv6 mismatch"' \
		'check_line_exact "ptr-record=$(LAN_RASPBERRYPI),raspberrypi.$(LAN_DOMAIN)" "raspberrypi IPv4 PTR mismatch"' \
		'check_line_exact "ptr-record=$(LAN6_RASPBERRYPI),raspberrypi.$(LAN_DOMAIN)" "raspberrypi IPv6 PTR mismatch"' \
		'check_line_exact "server=$(LAN_NAS)#$(UNBOUND_PORT)" "Unbound IPv4 upstream mismatch"' \
		'check_line_exact "server=$(LAN6_NAS)#$(UNBOUND_PORT)" "Unbound IPv6 upstream mismatch"' \
		'check_line_exact "server=/#/9.9.9.9" "fallback Quad9 IPv4 missing"' \
		'check_line_exact "server=/#/2620:fe::fe" "fallback Quad9 IPv6 missing"' \
		'check_line_exact "server=/#/130.59.31.248" "fallback Switch IPv4 missing"' \
		'check_line_exact "server=/#/2001:620:0:ff::2" "fallback Switch IPv6 missing"' \
		'check_line_exact "server=/#/185.95.218.42" "fallback Digitale Gesellschaft IPv4 missing"' \
		'check_line_exact "server=/#/2a05:fc84::42" "fallback Digitale Gesellschaft IPv6 missing"' \
		'check_line_exact "dhcp-option=6,$(LAN_ROUTER)" "DHCPv4 DNS mismatch"' \
		'check_line_exact "dhcp-option=option6:dns-server,[$(LAN6_ROUTER)]" "DHCPv6 DNS mismatch"' \
		'check_line_exact "dhcp-option=15,$(LAN_DOMAIN)" "DHCP option 15 domain mismatch"' \
		'check_line_exact "all-servers" "all-servers concurrency flag missing"' \
		'check_line_exact "domain-needed" "domain-needed hygiene flag missing"' \
		'check_line_exact "bogus-priv" "bogus-priv hygiene flag missing"' \
		'echo "dnsmasq.conf.add validated successfully"' \
		| ssh "$(SSH_HOST_ROUTER)" "sh -s"

.PHONY: router-dnsmasq-test
router-dnsmasq-test: router-dnsmasq-validate
	@echo "🧪 Running dnsmasq syntax check on router..."
	@ssh "$(SSH_HOST_ROUTER)" "dnsmasq --test"

.PHONY: router-dnsmasq-restart
router-dnsmasq-restart: router-dnsmasq-test
	@echo "⚙️ Evaluating dnsmasq service restart status..."
	@ssh "$(SSH_HOST_ROUTER)" '\
		touch /jffs/dnsmasq-config.ready; \
		if [ -f /jffs/homelab_dnsmasq_changed ]; then \
			echo "🔄 dnsmasq configuration changed — restarting dnsmasq service"; \
			rm -f /jffs/homelab_dnsmasq_changed; \
			service restart_dnsmasq; \
			echo "🟢 dnsmasq restarted cleanly"; \
		else \
			echo "✅ dnsmasq configuration unchanged — no restart required"; \
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
router-dnsmasq-invariants: router-ssh-check router-install-scripts
	@if [ "$(or $(VERBOSE),0)" -ge 1 ]; then echo "🛡️ Validating dnsmasq invariants on router"; fi; \
	ssh "$(SSH_HOST_ROUTER)" '\
		set -e; \
		pidof dnsmasq >/dev/null || { echo "❌ dnsmasq not running"; exit 1; }; \
		nslookup localhost 127.0.0.1 >/dev/null 2>&1 || { echo "❌ dnsmasq not serving local domain"; exit 1; }; \
		[ -f /jffs/configs/dnsmasq.conf.add ] || { echo "❌ /jffs/configs/dnsmasq.conf.add missing"; exit 1; }; \
		grep -q "server=$(LAN_NAS)#$(UNBOUND_PORT)" /jffs/configs/dnsmasq.conf.add || { echo "❌ Missing IPv4 upstream to Unbound"; exit 1; }; \
		grep -q "server=$(LAN6_NAS)#$(UNBOUND_PORT)" /jffs/configs/dnsmasq.conf.add || { echo "❌ Missing IPv6 upstream to Unbound"; exit 1; }; \
		nslookup localhost $(LAN_ROUTER) >/dev/null 2>&1 || { echo "❌ dnsmasq IPv4/53 unreachable"; exit 1; }; \
		nslookup localhost $(LAN6_ROUTER) >/dev/null 2>&1 || { echo "❌ dnsmasq IPv6/53 unreachable"; exit 1; }; \
		iptables -L HOMELAB_INPUT -n | grep -q "udp dpt:53" || { echo "❌ Missing UDP/53 ACCEPT in HOMELAB_INPUT"; exit 1; }; \
		iptables -L HOMELAB_INPUT -n | grep -q "tcp dpt:53" || { echo "❌ Missing TCP/53 ACCEPT in HOMELAB_INPUT"; exit 1; }; \
		ip6tables -L HOMELAB_INPUT -n | grep -q "udp dpt:53" || { echo "❌ Missing IPv6 UDP/53 ACCEPT in HOMELAB_INPUT"; exit 1; }; \
		ip6tables -L HOMELAB_INPUT -n | grep -q "tcp dpt:53" || { echo "❌ Missing IPv6 TCP/53 ACCEPT in HOMELAB_INPUT"; exit 1; }; \
		if grep -q "constructor:br0" /jffs/configs/dnsmasq.conf.add; then \
			echo "❌ Illegal RA constructor detected (global prefix leakage risk)"; \
			exit 1; \
		fi; \
	'; \
	if [ "$(or $(VERBOSE),0)" -ge 1 ]; then echo "🟢 dnsmasq invariants satisfied"; fi
