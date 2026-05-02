# mk/router/10_bootstrap.mk
# ------------------------------------------------------------
# 1. MACROS & ENVIRONMENT
# ------------------------------------------------------------

ifeq ($(strip $(REPO_ROOT)),)
  $(error ❌ REPO_ROOT not set)
endif

REQUIRED_VARS := \
  INSTALL_FILE_IF_CHANGED \
  INSTALL_FILES_IF_CHANGED \
  INSTALL_IF_CHANGED_EXIT_CHANGED \
  run_as_root \
  ROUTER_SCRIPTS_OWNER \
  ROUTER_SCRIPTS_GROUP \
  ROUTER_SCRIPTS \
  ROUTER_SCRIPTS_MODE

# Only enforce required-vars guard if secrets file exists
ifneq ($(filter router-% wg-% dns-% firewall-% converge-% all,$(MAKECMDGOALS)),)
  MISSING_VARS := $(strip $(foreach v,$(REQUIRED_VARS),$(if $(strip $($(v))),, $(v))))
  ifneq ($(strip $(MISSING_VARS)),)
	$(error ❌ Missing required variables: $(subst  ,, $(MISSING_VARS)))
  endif
endif

define PUSH_ROUTER_SCRIPTS_BATCH
	for f in $(ROUTER_SCRIPT_FILES); do \
		src="$(REPO_ROOT)/router/jffs/scripts/$$f"; \
		dst="$(ROUTER_SCRIPTS)/$$f"; \
		$(INSTALL_FILE_IF_CHANGED) "" "" "$$src" \
			"$$router_addr" "$$router_ssh_port" "$$dst" \
			"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "$(ROUTER_SCRIPTS_MODE)"; \
	done
endef

define PUSH_ROUTER_SCRIPT
	find ~/.ssh -maxdepth 1 -type s -name 'cm-*' -delete 2>/dev/null || true

	if [ -z "$(VERBOSE)" ] || [ "$(VERBOSE)" -eq 0 ]; then \
	env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) $(INSTALL_FILE_IF_CHANGED) -q \
		"" "" $(1) \
		$$router_addr $$router_ssh_port $(2) \
		$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE); \
	else \
	env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) $(INSTALL_FILE_IF_CHANGED) \
		"" "" $(1) \
		$$router_addr $$router_ssh_port $(2) \
		$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE); \
	fi; \
	rc=$$?; \
	if [ $$rc -ne 0 ] && [ $$rc -ne $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
	echo "❌ Failed to push $(1) to $$router_addr (rc=$$rc)"; \
	exit $$rc; \
	fi
endef

# ------------------------------------------------------------
# 2. PHASE 0: INFRASTRUCTURE & BOOTSTRAP
# ------------------------------------------------------------

.PHONY: ensure-default-gateway
ensure-default-gateway: secrets-ready
	@$(WITH_SECRETS) \
		if ! ip route show default | grep -q "$$router_addr"; then \
			echo "⚠️ Default gateway missing! Restoring path to $$router_addr..."; \
			$(run_as_root) ip route add default via "$$router_addr" dev $(LAN_IFACE) 2>/dev/null || true; \
			echo "✅ Default gateway restored"; \
		else \
			echo "🟢 Default gateway OK"; \
		fi

.PHONY: router-bootstrap-run-as-root
router-bootstrap-run-as-root: secrets-ready ensure-default-gateway
	@echo "🛡️ Bootstrapping run-as-root on router"
	@$(WITH_SECRETS) \
		router_ssh="ssh -p $$router_ssh_port $$router_user@$$router_addr"; \
		$$router_ssh 'set -e; mkdir -p /jffs/scripts; cat > /jffs/scripts/run-as-root; chmod 0755 /jffs/scripts/run-as-root' \
		< $(REPO_ROOT)/router/jffs/scripts/run-as-root.sh
	@echo "✅ run-as-root installed"

ROUTER_ULA_FILE := /etc/homelab/router-ula
ROUTER_ULA_VALUE := fd89:7a3b:42c0::1

.tmp/router-ula:
	@mkdir -p .tmp
	@printf "%s\n" "$(ROUTER_ULA_VALUE)" > .tmp/router-ula

.PHONY: ensure-router-ula
ensure-router-ula: secrets-ready .tmp/router-ula router-bootstrap-run-as-root
	@$(WITH_SECRETS) \
		env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
			$(INSTALL_FILE_IF_CHANGED) \
				"" "" ".tmp/router-ula" \
				"$$router_addr" "$$router_ssh_port" "$(ROUTER_ULA_FILE)" \
				"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0644" \
		|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]

# ------------------------------------------------------------
# 3. DEPLOYMENT
# ------------------------------------------------------------

ROUTER_SCRIPT_FILES := \
	caddy-reload.sh certs-create.sh certs-deploy.sh common.sh \
	gen-client-cert-wrapper.sh generate-client-cert.sh \
	firewall-start \
	wg-firewall.sh

.PHONY: router-install-%
router-install-%: | router-bootstrap-run-as-root
	@src=$(REPO_ROOT)/router/jffs/scripts/$*; \
	if [ ! -f "$$src" ]; then \
	  echo "⚠️ Skipping $* — source $$src not found"; \
	else \
	  $(call PUSH_ROUTER_SCRIPT, $$src, $(ROUTER_SCRIPTS)/$*); \
	fi

.PHONY: router-install-scripts
router-install-scripts: install-ssh-config router-bootstrap-run-as-root | ensure-router-ula
	@$(WITH_SECRETS) $(call PUSH_ROUTER_SCRIPTS_BATCH)
	@echo "✅ Router scripts installed"

.PHONY: router-dnsmasq-sync
router-dnsmasq-sync: secrets-ready | $(INSTALL_FILES_IF_CHANGED) router-bootstrap-run-as-root ensure-router-ula
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
# 4. PROVISIONING
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

.PHONY: router-dhcp-static-ensure
router-dhcp-static-ensure: secrets-ready | ensure-router-ula
	@echo "🛡️ Enforcing DHCP static leases via NVRAM"
	@$(WITH_SECRETS) \
		router_ssh="ssh -p $$router_ssh_port $$router_user@$$router_addr"; \
		$$router_ssh 'set -e; \
			current="$$(nvram get dhcp_staticlist || true)"; \
			desired="$(STATIC_DHCP)"; \
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

.PHONY: router-ddns
router-ddns: router-install-scripts ddns-conf-generate router-bootstrap-run-as-root prereqs-helper-scripts | ensure-router-ula
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
# 5. ORCHESTRATION
# ------------------------------------------------------------

export ROUTER_BOOTSTRAP

ROUTER_CONVERGE_DEPS := \
	ensure-default-gateway \
	ensure-router-ula \
	router-install-scripts \
	router-provision-nvram \
	router-dhcp-static-ensure \
	router-dnsmasq-sync \
	install-ssh-config

.PHONY: router-bootstrap
router-bootstrap: export ROUTER_BOOTSTRAP=1
router-bootstrap: $(ROUTER_CONVERGE_DEPS) router-ddns router-firewall-install router-install-ca | ensure-router-ula
	@echo "✅ Router bootstrap complete"

.PHONY: router-all
router-all: secrets-ready $(ROUTER_CONVERGE_DEPS) | ensure-router-ula
	@echo "🚀 Router base converge complete"

.PHONY: router-firewall-install
router-firewall-install: | ensure-router-ula
	@true

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
