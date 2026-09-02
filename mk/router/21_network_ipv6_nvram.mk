# mk/router/21_network_ipv6_nvram.mk
# ------------------------------------------------------------
# Router network stack (IPv6 + NVRAM converge):
#   - IPv6 ULA / NVRAM provisioning
#   - Router RA policy
#   - DHCPv6-PD hook
#   - IPv6 converge
#   - LAN domain setter
#   - DDNS deploy + execution
#   - SSH invariants
#   - Unified NVRAM converge
# ------------------------------------------------------------

define NVRAM_GET_BOTH
ssh "$(SSH_HOST_ROUTER)" 'v=$$(nvram get sshd_enable 2>/dev/null); echo "$${v:-unset}"; v=$$(nvram get sshd_pass 2>/dev/null); echo "$${v:-unset}"'
endef

.PHONY: router-ssh-invariants
router-ssh-invariants: router-ssh-check
	@vals=$$($(call NVRAM_GET_BOTH)); \
	set -- $$vals; \
	cur_enable="$$1"; \
	cur_pass="$$2"; \
	if [ "$$cur_enable" = "2" ] && [ "$$cur_pass" = "1" ]; then \
		if [ "$(VERBOSE)" -ge 1 ]; then \
			echo "🟢 Router SSH invariants already correct : sshd_enable=2, sshd_pass=1"; \
		fi; \
	else \
		ssh "$(SSH_HOST_ROUTER)" "nvram set sshd_enable=2; nvram set sshd_pass=1; nvram commit; service restart_ssh >/dev/null 2>&1"; \
		vals=$$($(call NVRAM_GET_BOTH)); \
		set -- $$vals; \
		new_enable="$$1"; \
		new_pass="$$2"; \
		if [ "$$new_enable" = "2" ] && [ "$$new_pass" = "1" ]; then \
			echo "✅ Router SSH invariants enforced (sshd_enable=$$new_enable, sshd_pass=$$new_pass)"; \
		else \
			echo "❌ Router SSH invariants enforcement failed: sshd_enable=$$new_enable sshd_pass=$$new_pass"; \
			exit 1; \
		fi; \
	fi

# ------------------------------------------------------------
# LAN domain — pure NVRAM setter
# ------------------------------------------------------------

.PHONY: router-lan-domain
router-lan-domain: | router-ssh-check secret-vars-check
	@LAN_DOMAIN="$$( $(call SECRET,lan_domain) )"; \
	PUBLIC_DOMAIN="$(DOMAIN)"; \
	lan_lc="$$(printf '%s' "$$LAN_DOMAIN" | tr A-Z a-z)"; \
	pub_lc="$$(printf '%s' "$$PUBLIC_DOMAIN" | tr A-Z a-z)"; \
	case "$$lan_lc" in *.$$pub_lc|$$pub_lc) \
		echo "❌ Unsafe LAN_DOMAIN '$$LAN_DOMAIN' (suffix of '$$PUBLIC_DOMAIN')"; \
		echo "   dnsmasq would rewrite public DNS (FQDN synthesis)."; \
		echo "   Refusing to set unsafe LAN domain in NVRAM."; \
		exit 1; \
		;; \
	esac; \
	cur_lan_domain="$$( ssh "$(SSH_HOST_ROUTER)" "nvram get lan_domain 2>/dev/null || true" )"; \
	if [ "$$cur_lan_domain" = "$$LAN_DOMAIN" ]; then \
		test -n "$(VERBOSE)" || echo "🌐 LAN domain already converged ('$$LAN_DOMAIN')"; \
		exit 0; \
	fi; \
	ssh "$(SSH_HOST_ROUTER)" "\
		nvram set lan_domain='$$LAN_DOMAIN'; \
		echo \"🌐 LAN domain staged: '$$LAN_DOMAIN' (commit in router-nvram-converge)\"; \
		touch /jffs/homelab_nvram_dirty; \
	"

# ------------------------------------------------------------
# DHCP static export (secrets)
# ------------------------------------------------------------

.PHONY: router-dhcp-static-export-secrets
router-dhcp-static-export-secrets: router-ssh-check
	@line="$$( ssh "$(SSH_HOST_ROUTER)" "nvram get dhcp_staticlist 2>/dev/null || true" )"; \
	printf 'DHCP static leases (paste into secrets.enc.yaml):\n\n'; \
	{ \
		for token in $$line; do \
			rest=$${token#<}; \
			rest=$${rest%>>}; \
			ip=$${rest#*>}; \
			printf '%s %s\n' "$$ip" "$$token"; \
		done; \
	} \
	| sort -t. -k1,1n -k2,2n -k3,3n -k4,4n \
	| awk '{ i++; printf "dhcp_static_%d=\"%s\"\n", i, $$2 }';

define NVRAM_GET_IPV6
ssh "$(SSH_HOST_ROUTER)" "\
	set +u; \
	nvram get ipv6_ula_prefix 2>/dev/null || echo unset; \
	nvram get ipv6_lan_addr 2>/dev/null || echo unset; \
	nvram get ipv6_lan_prefix 2>/dev/null || echo unset"
endef

.PHONY: router-provision-nvram
router-provision-nvram: secrets-ready | ensure-router-ula router-ssh-check
	@set +u; \
	if [ "$(VERBOSE)" -ge 1 ]; then echo "🛡️ Syncing Router NVRAM (ULA only — DNS handled by dns-enforcer) (no commit)"; fi; \
	vals="$$( $(call NVRAM_GET_IPV6) )"; \
	set -- $${vals:-unset unset unset}; \
	cur_prefix="$$1"; \
	cur_lan_addr="$$2"; \
	cur_lan_prefix="$$3"; \
	\
	if [ -z "$$cur_prefix" ] || [ "$$cur_prefix" = "unset" ] || \
	   [ -z "$$cur_lan_addr" ] || [ "$$cur_lan_addr" = "unset" ] || \
	   [ -z "$$cur_lan_prefix" ] || [ "$$cur_lan_prefix" = "unset" ]; then \
		echo "ℹ️ IPv6 is not active or uninitialized on the router NVRAM."; \
		if [ "$(VERBOSE)" -ge 1 ]; then \
			echo "👉 Please log into the router web interface, enable Native IPv6, and set the LAN prefix length to 64."; \
		fi; \
	fi; \
	# --- Converge ipv6_ula_prefix --- \
	if [ -z "$$cur_prefix" ] || [ "$$cur_prefix" = "unset" ] || [ "$$cur_prefix" != "$(ULA_PREFIX_NVRAM)" ]; then \
		ssh "$(SSH_HOST_ROUTER)" "\
			nvram set ipv6_ula_prefix='$(ULA_PREFIX_NVRAM)'; \
			nvram set ipv6_ula_enable=1; \
			touch /jffs/homelab_nvram_dirty"; \
		echo "🟢 ULA prefix staged: ipv6_ula_prefix=$(ULA_PREFIX_NVRAM)"; \
	else \
		if [ "$(VERBOSE)" -ge 1 ]; then \
			echo "🟢 ULA prefix already converged (ipv6_ula_prefix=$(ULA_PREFIX_NVRAM))"; \
		fi; \
	fi; \
	\
	# --- Converge ipv6_lan_addr --- \
	if [ -z "$$cur_lan_addr" ] || [ "$$cur_lan_addr" = "unset" ] || [ "$$cur_lan_addr" != "$(LAN6_ROUTER)" ]; then \
		ssh "$(SSH_HOST_ROUTER)" "\
			nvram set ipv6_lan_addr='$(LAN6_ROUTER)'; \
			touch /jffs/homelab_nvram_dirty"; \
		echo "🟢 ULA LAN addr staged: ipv6_lan_addr=$(LAN6_ROUTER)"; \
	else \
		if [ "$(VERBOSE)" -ge 1 ]; then \
			echo "🟢 ULA LAN addr already converged (ipv6_lan_addr=$(LAN6_ROUTER))"; \
		fi; \
	fi; \
	\
	# --- Converge ipv6_lan_prefix --- \
	if [ -z "$$cur_lan_prefix" ] || [ "$$cur_lan_prefix" = "unset" ] || [ "$$cur_lan_prefix" != "$(LAN6_LAN_PREFIX_LEN)" ]; then \
		ssh "$(SSH_HOST_ROUTER)" "\
			nvram set ipv6_lan_prefix='$(LAN6_LAN_PREFIX_LEN)'; \
			touch /jffs/homelab_nvram_dirty"; \
		echo "🟢 ULA LAN prefix staged: ipv6_lan_prefix=$(LAN6_LAN_PREFIX_LEN)"; \
	else \
		if [ "$(VERBOSE)" -ge 1 ]; then \
			echo "🟢 ULA LAN prefix already converged (ipv6_lan_prefix=$(LAN6_LAN_PREFIX_LEN))"; \
		fi; \
	fi


# ------------------------------------------------------------
# Router RA policy
# ------------------------------------------------------------

.PHONY: router-ra-policy
router-ra-policy: router-bootstrap-primitives router-ssh-check
	@if [ "$(VERBOSE)" -ge 1 ]; then \
		echo "🛡️ Enforcing router RA policy (enable default route in RA) (no commit, no restart)"; \
	fi

	@cur="$$( ssh "$(SSH_HOST_ROUTER)" "nvram get ipv6_accept_ra 2>/dev/null || echo unset" )"; \
	\
	if [ "$$cur" = "2" ]; then \
		if [ "$(VERBOSE)" -ge 1 ]; then \
			echo "🟢 RA policy already converged (ipv6_accept_ra=2)"; \
		fi; \
		exit 0; \
	fi; \
	\
	ssh "$(SSH_HOST_ROUTER)" "\
		nvram set ipv6_accept_ra=2; \
		touch /jffs/homelab_nvram_dirty"; \
	\
	echo "🟢 RA policy staged: ipv6_accept_ra=2 (commit in router-nvram-converge)"

# ------------------------------------------------------------
# DDNS deploy + execution
# ------------------------------------------------------------

.PHONY: router-ddns
router-ddns: secrets-ready ensure-router-ula router-ssh-check
	@if [ "$(VERBOSE)" -ge 1 ]; then \
		echo "📡 Deploying DDNS configuration to router"; \
	fi
	@$(call WITH_SECRETS, sh -c '\
		set -e; \
		umask 077; \
		printf "%s\n%s\n%s\n%s\n" \
			"DNS_TOPDOMAIN_NAME='\$$ddns_topdomain'" \
			"DDNS_NETBIRD_DOMAIN='\$$ddns_netbird_domain'" \
			"DDNSUSERNAME='\$$ddns_username'" \
			"DDNSPASSWORD='\$$ddns_password'" \
			> "$(TMP_DDNS_CONF)"; \
		\
		env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
			$(INSTALL_FILE_IF_CHANGED) \
				"" "" "$(TMP_DDNS_CONF)" \
				"$$ROUTER_ADDR" "$$ROUTER_SSH_PORT" "/jffs/scripts/.ddns_confidential" \
				"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0600" \
			|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; \
		rm -f "$(TMP_DDNS_CONF)"; \
	')

	@if [ "$(VERBOSE)" -ge 1 ]; then \
		echo "🔄 Executing DDNS update"; \
	fi
	@ssh "$(SSH_HOST_ROUTER)" '$(ROUTER_SCRIPTS)/ddns-start'

	@if [ "$(VERBOSE)" -ge 1 ]; then \
		echo "🟢 DDNS update complete"; \
	fi

# ------------------------------------------------------------
# DHCPv6-PD hook
# ------------------------------------------------------------

.PHONY: router-dhcp6c-hook-converge
router-dhcp6c-hook-converge: router-ssh-check
	@if [ "$(VERBOSE)" -ge 1 ]; then \
		echo "🛡️ Ensuring dhcp6c-state hook exists"; \
	fi
	@ssh "$(SSH_HOST_ROUTER)" 'set -e; \
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

# ------------------------------------------------------------
# Unified NVRAM + dnsmasq/radvd converge (dirty-flag based)
# ------------------------------------------------------------


define ROUTER_NVRAM_CONVERGE_SH
set -e
RESTART=0

if [ -f /jffs/homelab_nvram_dirty ]; then
	nvram commit
	rm -f /jffs/homelab_nvram_dirty
	RESTART=1
fi

if [ -f /jffs/homelab_dnsmasq_changed ]; then
	rm -f /jffs/homelab_dnsmasq_changed
	RESTART=1
fi

if [ "$$RESTART" -eq 1 ]; then
	service restart_dnsmasq
	service restart_radvd || true
	exit 10
else
	exit 0
fi
endef


.PHONY: router-nvram-converge
router-nvram-converge: \
	router-dhcp-range-ensure \
	router-dhcp-static-ensure \
	router-lan-domain \
	router-provision-nvram \
	router-ra-policy \
	router-dnsmasq-sync \
	router-ssh-check
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🛡️ Committing NVRAM and restarting services (minimal restarts)"; fi; \
	ssh "$(SSH_HOST_ROUTER)" '\
		set -e; \
		RESTART=0; \
		\
		if [ -f /jffs/homelab_nvram_dirty ]; then \
			echo "📥 NVRAM dirty ➡️ committing"; \
			nvram commit; \
			rm -f /jffs/homelab_nvram_dirty; \
			RESTART=1; \
		fi; \
		\
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
			if [ "$(VERBOSE)" -ge 1 ]; then echo "✅ No changes ➡️ no restarts"; fi;\
		fi; \
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🟢 router-nvram-converge complete"; fi; \
	'

# ------------------------------------------------------------
# IPv6 converge
# ------------------------------------------------------------
.PHONY: router-ipv6-converge
router-ipv6-converge: router-nvram-converge router-dhcp6c-hook-converge router-ssh-check
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🛡️ IPv6 converge: checking PD hook + dnsmasq RA"; fi; \
	ssh "$(SSH_HOST_ROUTER)" '\
		set -e; \
		OLD_PREFIX="$$(cat /jffs/scripts/.ipv6_current_prefix 2>/dev/null || echo)"; \
		service start_dhcp6c || true; \
		NEW_PREFIX="$$(cat /jffs/scripts/.ipv6_current_prefix 2>/dev/null || echo)"; \
		if [ "$$OLD_PREFIX" != "$$NEW_PREFIX" ] || [ -f /jffs/homelab_ipv6_dirty ]; then \
			echo "🔄 IPv6 prefix changed or dirty ➡️ restarting services"; \
			rm -f /jffs/homelab_ipv6_dirty; \
			service restart_dnsmasq || true; \
			service restart_radvd || true; \
		else \
			if [ "$(VERBOSE)" -ge 1 ]; then echo "✅ IPv6 prefix unchanged ➡️ no restarts"; fi; \
		fi; \
		if [ "$(VERBOSE)" -ge 1 ]; then echo "🟢 router-ipv6-converge complete"; fi; \
	'