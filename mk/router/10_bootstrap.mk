# mk/router/10_bootstrap.mk
# ------------------------------------------------------------
# 1. MACROS & ENVIRONMENT
# ------------------------------------------------------------

# normalize REPO_ROOT to end with a slash (fail early if not set)
ifeq ($(strip $(REPO_ROOT)),)
  $(error ❌ REPO_ROOT not set)
endif
ifeq ($(shell echo $(REPO_ROOT) | sed -n 's/.*\/$$/yes/p'),)
  REPO_ROOT := $(REPO_ROOT)/
endif

# Load repo defaults if present; do not fail on first bootstrap.
-include $(REPO_ROOT)config/homelab.env

# list of required variables (add or remove names as needed)
REQUIRED_VARS := \
  INSTALL_FILE_IF_CHANGED \
  INSTALL_FILES_IF_CHANGED \
  INSTALL_IF_CHANGED_EXIT_CHANGED \
  run_as_root \
  HOMELAB_ENV_DST \
  ROUTER_SSH_PORT \
  ROUTER_USER \
  ROUTER_ADDR \
  ROUTER_SCRIPTS_OWNER \
  ROUTER_SCRIPTS_GROUP \
  ROUTER_SCRIPTS \
  ROUTER_SCRIPTS_MODE

# collect variables that are undefined or empty
MISSING_VARS := $(strip $(foreach v,$(REQUIRED_VARS),$(if $(strip $($(v))),, $(v))))

# single error if any are missing (comma separated)
ifeq ($(strip $(MISSING_VARS)),)
  # all good
else
  $(error ❌ Missing required variables: $(subst  ,, $(MISSING_VARS)))
endif

.NOTPARALLEL: \
	ensure-default-gateway \
	router-bootstrap-run-as-root \
	router-ddns

# Logic: Local Source -> Remote Router (9-argument signature)
define PUSH_ROUTER_SCRIPT
 	if [ -z "$(VERBOSE)" ] || [ "$(VERBOSE)" -eq 0 ]; then \
 	  env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) $(INSTALL_FILE_IF_CHANGED) -q \
 		"" "" $(1) \
 		$(ROUTER_ADDR) $(ROUTER_SSH_PORT) $(2) \
 		$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE); \
 	else \
 	  env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) $(INSTALL_FILE_IF_CHANGED) \
 		"" "" $(1) \
 		$(ROUTER_ADDR) $(ROUTER_SSH_PORT) $(2) \
 		$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE); \
 	fi; \
 	rc=$$?; \
 	if [ $$rc -ne 0 ] && [ $$rc -ne $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
 	  echo "❌ Failed to push $(1) to $(ROUTER_ADDR) (rc=$$rc)"; exit $$rc; \
 	fi
endef

# SSOT Calculation for NVRAM (strips host ID to create the /48 prefix)
ifeq ($(strip $(NAS_LAN_IP6)),)
  ULA_PREFIX_NVRAM :=
  $(warning NAS_LAN_IP6 is empty; ULA_PREFIX_NVRAM will be empty)
else
  ULA_PREFIX_NVRAM := $(shell echo "$(NAS_LAN_IP6)" | sed -n 's/::[0-9a-fA-F]*$$/::\/48/p')
  ifeq ($(strip $(ULA_PREFIX_NVRAM)),)
	$(warning Could not compute ULA_PREFIX_NVRAM from NAS_LAN_IP6=$(NAS_LAN_IP6))
  endif
endif

# ------------------------------------------------------------
# 2. PHASE 0: INFRASTRUCTURE & BOOTSTRAP
# ------------------------------------------------------------

.PHONY: ensure-default-gateway
ensure-default-gateway: | $(HOMELAB_ENV_DST) ## Ensure the IPv4 default route is present
	@if ! ip route show default | grep -q "$(ROUTER_ADDR)"; then \
		echo "⚠️ Default gateway missing! Restoring path to $(ROUTER_ADDR)..."; \
		$(run_as_root) ip route add default via $(ROUTER_ADDR) dev $(LAN_IFACE) 2>/dev/null || true; \
	fi

.PHONY: router-bootstrap-run-as-root
router-bootstrap-run-as-root: ensure-default-gateway | $(HOMELAB_ENV_DST)
	@echo "🛡️ Bootstrapping run-as-root on router"
	@$(ROUTER_SSH) 'set -e; mkdir -p /jffs/scripts; cat > /jffs/scripts/run-as-root; chmod 0755 /jffs/scripts/run-as-root' \
		< $(REPO_ROOT)router/jffs/scripts/run-as-root.sh

# ------------------------------------------------------------
# 3. DEPLOYMENT (FILE SYNC & TEMPLATING)
# ------------------------------------------------------------

# Authoritative script list
ROUTER_SCRIPT_FILES := \
	caddy-reload.sh certs-create.sh certs-deploy.sh common.sh \
	gen-client-cert-wrapper.sh generate-client-cert.sh \
	firewall-start

.PHONY: router-install-%
router-install-%: | router-bootstrap-run-as-root $(HOMELAB_ENV_DST)
	@src=$(REPO_ROOT)router/jffs/scripts/$*; \
	if [ ! -f "$$src" ]; then \
	  echo "⚠️  Skipping $* — source $$src not found"; \
	else \
	  $(call PUSH_ROUTER_SCRIPT, $$src, $(ROUTER_SCRIPTS)/$*); \
	fi

.PHONY: router-install-scripts
router-install-scripts: install-ssh-config router-bootstrap-run-as-root $(addprefix router-install-,$(ROUTER_SCRIPT_FILES)) | $(HOMELAB_ENV_DST)
	@# Remove only stale SSH control sockets older than 10 minutes to avoid disrupting active sessions
	@test -d ~/.ssh || mkdir -p ~/.ssh
	@find ~/.ssh -maxdepth 1 -type s -name 'cm-*' -mmin +10 -print -delete || true
	@echo "✅ Router scripts installed"

.PHONY: router-dnsmasq-sync
router-dnsmasq-sync: | $(HOMELAB_ENV_DST) $(INSTALL_FILES_IF_CHANGED) router-bootstrap-run-as-root
	@echo "📡 Templating and Syncing DNS configuration for $(DOMAIN)..."
	@mkdir -p .tmp
	@sed "s|\$${NAS_LAN_IP}|$(NAS_LAN_IP)|g; s|\$${DOMAIN}|$(DOMAIN)|g" \
		$(REPO_ROOT)router/jffs/configs/dnsmasq.conf.add > .tmp/dnsmasq.conf.add
	@DNS_CHANGED=0; export DNS_CHANGED; \
	{ $(INSTALL_FILES_IF_CHANGED) DNS_CHANGED \
		"" "" ".tmp/dnsmasq.conf.add" "$(ROUTER_ADDR)" "$(ROUTER_SSH_PORT)" "/jffs/configs/dnsmasq.conf.add" \
		"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0644" \
		"" "" "$(REPO_ROOT)router/jffs/configs/hosts.add" "$(ROUTER_ADDR)" "$(ROUTER_SSH_PORT)" "/jffs/configs/hosts.add" \
		"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0644" \
		|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; } && \
	if [ "$$DNS_CHANGED" -eq 1 ]; then \
		echo "🔄 DNS changed. Restarting service..."; \
		$(ROUTER_SSH) 'if command -v service >/dev/null 2>&1 && service restart_dnsmasq >/dev/null 2>&1; then echo restarted; else killall -HUP dnsmasq 2>/dev/null || /etc/init.d/dnsmasq restart 2>/dev/null || true; fi';
	fi

# ------------------------------------------------------------
# 4. PROVISIONING (STATE ENFORCEMENT)
# ------------------------------------------------------------

.PHONY: router-provision-nvram
router-provision-nvram: | $(HOMELAB_ENV_DST)
	@echo "🛡️ Syncing Router NVRAM (ULA/RDNSS) using SSOT"
	@$(ROUTER_SSH) 'set -e; \
		if [ "$$(nvram get ipv6_ula_prefix)" != "$(ULA_PREFIX_NVRAM)" ] || [ "$$(nvram get ipv6_dns1)" != "$(ROUTER_ULA_IP6)" ]; then \
			echo "⚙️ Updating NVRAM values..."; \
			nvram set ipv6_ula_enable=1; \
			nvram set ipv6_ula_prefix=$(ULA_PREFIX_NVRAM); \
			nvram set ipv6_dns1=$(ROUTER_ULA_IP6); \
			nvram set ipv6_dns61_x=$(ROUTER_ULA_IP6); \
			nvram commit || { echo "❌ nvram commit failed"; exit 1; }; \
			echo "✅ NVRAM updated."; \
		else \
			echo "✅ NVRAM already converged."; \
		fi'

.PHONY: router-ddns
router-ddns: router-bootstrap-run-as-root prereqs-helper-scripts ddns-secret-ensure | $(HOMELAB_ENV_DST)
	@echo "🔄 Executing DDNS update"
	@# Implementation matches your existing deploy-then-run logic
	@$(ROUTER_SSH) '$(ROUTER_SCRIPTS)/ddns-start'

# ------------------------------------------------------------
# 5. ORCHESTRATION
# ------------------------------------------------------------

export ROUTER_BOOTSTRAP

# --- Shared Convergence Baseline ---
ROUTER_CONVERGE_DEPS := \
	ensure-default-gateway \
	router-install-scripts \
	router-provision-nvram \
	router-dnsmasq-sync \
	install-ssh-config

.PHONY: router-bootstrap
router-bootstrap: export ROUTER_BOOTSTRAP=1
router-bootstrap: $(ROUTER_CONVERGE_DEPS) \
	router-ddns \
	router-firewall-install \
	router-install-ca
	@echo "✅ Router bootstrap complete"

.PHONY: router-all
router-all: $(ROUTER_CONVERGE_DEPS) \
	router-firewall-started
	@echo "🚀 Router base converge complete"