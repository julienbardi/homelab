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

# ------------------------------------------------------------
# router-ssh-invariants:
# Enforces LAN-only SSH by setting:
#   ssh_wan=0  ➡️ disable SSH on WAN
#   ssh_lan=1  ➡️ enable SSH on LAN
# AsusWRT defaults to WAN-enabled SSH when ssh_wan is unset.
# This target makes the invariant explicit and idempotent.
# ------------------------------------------------------------

.PHONY: router-ssh-invariants
router-ssh-invariants: router-ssh-check
	@echo "🛡️ Enforcing router SSH invariants (LAN-only SSH)"
	@ssh "$(SSH_HOST_ROUTER)" "\
		set -e; \
		cur_wan=\$$(nvram get ssh_wan || echo unset); \
		cur_lan=\$$(nvram get ssh_lan || echo unset); \
		\
		# ssh_wan converge
		if [ \"\$$cur_wan\" != \"0\" ]; then \
			nvram set ssh_wan=0; \
			echo \"🟢 SSH invariant staged: ssh_wan=0 (commit now)\"; \
			nvram commit; \
			service restart_ssh; \
			exit 0; \
		fi; \
		\
		# ssh_lan converge
		if [ \"\$$cur_lan\" != \"1\" ]; then \
			nvram set ssh_lan=1; \
			echo \"🟢 SSH invariant staged: ssh_lan=1 (commit now)\"; \
			nvram commit; \
			service restart_ssh; \
			exit 0; \
		fi; \
		\
		# idempotent case
		test -z \"$(VERBOSE)\" || echo \"✅ SSH invariants already enforced (ssh_wan=0, ssh_lan=1)\"; \
	"

# ------------------------------------------------------------
# LAN domain — pure NVRAM setter
# ------------------------------------------------------------

.PHONY: router-lan-domain
router-lan-domain: | router-ssh-check
	@LAN_DOMAIN="$$( $(call WITH_SECRETS, sh -c 'echo "$$lan_domain"' ) )"; \
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
	ssh "$(SSH_HOST_ROUTER)" "\
		set -e; \
		cur=\$$(nvram get lan_domain 2>/dev/null || true); \
		if [ \"\$$cur\" = \"$$LAN_DOMAIN\" ]; then \
			test -z \"$(VERBOSE)\" || echo \"🌐 LAN domain already converged ('$${LAN_DOMAIN}')\"; \
			exit 0; \
		fi; \
		nvram set lan_domain=\"$$LAN_DOMAIN\"; \
		echo \"🌐 LAN domain staged: '$$LAN_DOMAIN' (commit in router-nvram-converge)\"; \
		touch /jffs/homelab_nvram_dirty; \
	"

# ------------------------------------------------------------
# DHCP static export (secrets)
# ------------------------------------------------------------

.PHONY: router-dhcp-static-export-secrets
router-dhcp-static-export-secrets: router-ssh-check
	@echo '🔍 router-dhcp-static-export-secrets v7-sorted'; \
	tmp=$$(mktemp); \
	echo '🔍 SSH CMD: ssh '"$(SSH_HOST_ROUTER)"' '\''nvram get dhcp_staticlist 2>/dev/null || true'\'''; \
	ssh "$(SSH_HOST_ROUTER)" 'nvram get dhcp_staticlist 2>/dev/null || true' > "$$tmp"; \
	line=$$(cat "$$tmp"); \
	printf 'DHCP static leases (paste into secrets.enc.yaml):\n\n'; \
	{ \
		for token in $$line; do \
			rest=$${token#<}; \
			rest=$${rest%>>}; \
			ip=$${rest#*>}; \
			printf '%s %s\n' "$$ip" "$$token"; \
		done; \
	} | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | \
	awk '{ \
		i++; \
		printf "dhcp_static_%d=\"%s\"\n", i, $$2; \
	}'; \
	rm -f "$$tmp"; \
	echo '🔍 v8 done'

# VERSION: 81
# ============================================================
# mk/router/21_network_ipv6_nvram.mk — Router NVRAM ULA Sync
# ============================================================
# Fix: Mark router-provision-nvram as a drop-in replacement
# and lock the synchronized nvram convergence logic.
# ============================================================

.PHONY: router-provision-nvram
router-provision-nvram: secrets-ready | ensure-router-ula router-ssh-check
	@echo "🛡️ Syncing Router NVRAM (ULA only — DNS handled by dns-enforcer) (no commit)"
	@$(call WITH_SECRETS, \
	    export ULA_PREFIX_NVRAM="$${ULA_PREFIX:-fd89:7a3b:42c0::/48}"; \
	    export ROUTER_ULA_IP6="$${ROUTER_ULA_IP6:-fd89:7a3b:42c0::1}"; \
	    ssh "$(SSH_HOST_ROUTER)" "\
	        set -e; \
	        cur_prefix=\$$(nvram get ipv6_ula_prefix 2>/dev/null || echo); \
	        cur_lan_addr=\$$(nvram get ipv6_lan_addr 2>/dev/null || echo); \
	        \
	        if [ \"\$$cur_prefix\" != \"$$ULA_PREFIX_NVRAM\" ]; then \
	            nvram set ipv6_ula_prefix=\"$$ULA_PREFIX_NVRAM\"; \
	            nvram set ipv6_ula_enable=1; \
	            echo \"🟢 ULA prefix staged: ipv6_ula_prefix=$$ULA_PREFIX_NVRAM (commit in router-nvram-converge)\"; \
	            touch /jffs/homelab_nvram_dirty; \
	        else \
	            test -z \"$(VERBOSE)\" || echo \"✅ ULA prefix already converged (ipv6_ula_prefix=$$ULA_PREFIX_NVRAM)\"; \
	        fi; \
	        \
	        if [ \"\$$cur_lan_addr\" != \"$$ROUTER_ULA_IP6\" ]; then \
	            nvram set ipv6_lan_addr=\"$$ROUTER_ULA_IP6\"; \
	            nvram set ipv6_lan_prefix=48; \
	            echo \"🟢 ULA LAN addr staged: ipv6_lan_addr=$$ROUTER_ULA_IP6 (commit in router-nvram-converge)\"; \
	            touch /jffs/homelab_nvram_dirty; \
	        else \
	            test -z \"$(VERBOSE)\" || echo \"✅ ULA LAN addr already converged (ipv6_lan_addr=$$ROUTER_ULA_IP6)\"; \
	        fi; \
	    " \
	)

# ------------------------------------------------------------
# Router RA policy
# ------------------------------------------------------------

.PHONY: router-ra-policy
router-ra-policy: router-bootstrap-primitives router-ssh-check
	@echo "🛡️ Enforcing router RA policy (enable default route in RA) (no commit, no restart)"
	@ssh "$(SSH_HOST_ROUTER)" 'set -e; \
		cur="$$(nvram get ipv6_accept_ra || echo unset)"; \
		if [ "$$cur" = "2" ]; then \
			test -z "$(VERBOSE)" || echo "✅ RA policy already enforced (ipv6_accept_ra=2)"; \
			exit 0; \
		fi; \
		nvram set ipv6_accept_ra=2; \
		echo "🟢 RA policy staged: ipv6_accept_ra=2 (commit in router-nvram-converge)"; \
		touch /jffs/homelab_nvram_dirty; \
	'

# ------------------------------------------------------------
# DDNS deploy + execution
# ------------------------------------------------------------

.PHONY: router-ddns
router-ddns: secrets-ready ensure-router-ula router-ssh-check
	@echo "📡 Deploying DDNS configuration to router"
	@$(call WITH_SECRETS, sh -c '\
		set -e; \
		umask 077; \
		printf "%s\n%s\n%s\n" \
			"DNS_TOPDOMAIN_NAME='\$$ddns_topdomain'" \
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
	@echo "🔄 Executing DDNS update"
	@ssh "$(SSH_HOST_ROUTER)" '$(ROUTER_SCRIPTS)/ddns-start'
	@echo "🟢 DDNS update complete"

# ------------------------------------------------------------
# DHCPv6-PD hook
# ------------------------------------------------------------

.PHONY: router-dhcp6c-hook-converge
router-dhcp6c-hook-converge: router-ssh-check
	@echo "🛡️ Ensuring dhcp6c-state hook exists"
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

.PHONY: router-nvram-converge
router-nvram-converge: \
	router-dhcp-range-ensure \
	router-dhcp-static-ensure \
	router-lan-domain \
	router-provision-nvram \
	router-ra-policy \
	router-dnsmasq-sync \
	router-dnsmasq-conf \
	router-ssh-check
	@echo "🛡️ Committing NVRAM and restarting services (minimal restarts)"
	@ssh "$(SSH_HOST_ROUTER)" '\
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
			echo "✅ No changes ➡️ no restarts"; \
		fi; \
		echo "🟢 router-nvram-converge complete"; \
	'

# ------------------------------------------------------------
# IPv6 converge
# ------------------------------------------------------------

.PHONY: router-ipv6-converge
router-ipv6-converge: router-nvram-converge router-dhcp6c-hook-converge router-ssh-check
	@echo "🛡️ IPv6 converge: ensuring PD hook + dnsmasq RA"
	@ssh "$(SSH_HOST_ROUTER)" '\
		echo "🔄 Forcing DHCPv6-PD refresh"; \
		service start_dhcp6c || true; \
	'
