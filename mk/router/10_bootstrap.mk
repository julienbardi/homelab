# mk/router/10_bootstrap.mk
# ------------------------------------------------------------
# ROUTER BOOTSTRAP & BASELINE PROVISIONING (namespaced)
# ------------------------------------------------------------

.NOTPARALLEL: \
	ensure-default-gateway \
	router-bootstrap-run-as-root \
	router-ddns

# Router script sources inside the repository
ROUTER_SCRIPTS_SRC_DIR := $(REPO_ROOT)router/jffs/scripts

# ------------------------------------------------------------
# Internal Macro: Push script to Router via IFC v2
# ------------------------------------------------------------
# Logic: Local Source -> Remote Router (9-argument signature)
# 1: SRC_PATH, 2: DST_PATH
define PUSH_ROUTER_SCRIPT
	env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) $(INSTALL_FILE_IF_CHANGED) \
		"" "" $(1) \
		$(ROUTER_HOST) $(ROUTER_SSH_PORT) $(2) \
		$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE) \
		|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ];
endef

.PHONY: ensure-default-gateway
ensure-default-gateway: ## Ensure the IPv4 default route is present
	@if ! ip route show default | grep -q "$(GATEWAY_IP)"; then \
		echo "⚠️  Default gateway missing! Restoring path to $(GATEWAY_IP)..."; \
		$(run_as_root) ip route add default via $(GATEWAY_IP) dev $(LAN_IFACE) 2>/dev/null || true; \
	fi

# ------------------------------------------------------------
# DDNS Runtime Surface (deploy vs execute split; composed)
# ------------------------------------------------------------

.PHONY: router-ddns-deploy
router-ddns-deploy: router-bootstrap-run-as-root prereqs-helper-scripts \
	$(INSTALL_FILE_IF_CHANGED) \
	$(INSTALL_FILES_IF_CHANGED) \
	ddns-secret-ensure
	@echo "🔄 Syncing DDNS runtime surface to router"
	@DDNS_CHANGED=0; export DDNS_CHANGED; \
		{ $(INSTALL_FILES_IF_CHANGED) DDNS_CHANGED \
		"" "" "$(ROUTER_SCRIPTS_SRC_DIR)/ddns-start" \
		"$(ROUTER_HOST)" "$(ROUTER_SSH_PORT)" "$(ROUTER_SCRIPTS)/ddns-start" \
		"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0755" \
		"" "" "$(DDNS_SECRET_FILE)" \
		"$(ROUTER_HOST)" "$(ROUTER_SSH_PORT)" "/jffs/scripts/.ddns_confidential" \
		"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" "0600" \
		|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; }

.PHONY: router-ddns-run
router-ddns-run:
	@echo "🌐 Executing DDNS update on router"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '$(ROUTER_SCRIPTS)/ddns-start'

.PHONY: router-ddns
router-ddns: router-ddns-deploy router-ddns-run


# ------------------------------------------------------------
# Phase 0: Root bootstrap (transport ssh + cat)
# ------------------------------------------------------------

.PHONY: router-bootstrap-run-as-root
router-bootstrap-run-as-root: ensure-default-gateway
	@echo "🛡️ Bootstrapping run-as-root on router"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
		'mkdir -p /jffs/scripts && cat > /jffs/scripts/run-as-root && chmod 0755 /jffs/scripts/run-as-root' \
		< $(ROUTER_SCRIPTS_SRC_DIR)/run-as-root.sh

# ------------------------------------------------------------
# Router script installation (explicit, generic)
# ------------------------------------------------------------

# Authoritative list of router-managed scripts
# (DDNS is intentionally excluded — it owns its own surface)
ROUTER_SCRIPT_FILES := \
	caddy-reload.sh \
	certs-create.sh \
	certs-deploy.sh \
	common.sh \
	gen-client-cert-wrapper.sh \
	generate-client-cert.sh \
	provision-ipv6-ula.sh \
	wg-compile-alloc.sh \
	wg-compile-domain.sh \
	wg-compile-keys.sh \
	firewall-start \
	wg-policy-apply \
	wg-transport-apply

.PHONY: router-install-%
router-install-%: | router-bootstrap-run-as-root
	@$(call PUSH_ROUTER_SCRIPT, \
		$(ROUTER_SCRIPTS_SRC_DIR)/$*, \
		$(ROUTER_SCRIPTS)/$*)

ROUTER_INSTALL_TARGETS := $(addprefix router-install-,$(ROUTER_SCRIPT_FILES))

.PHONY: router-install-scripts
router-install-scripts: \
	install-ssh-config \
	$(INSTALL_FILE_IF_CHANGED) \
	router-bootstrap-run-as-root \
	$(ROUTER_INSTALL_TARGETS)
	@rm -f ~/.ssh/cm-*
	@echo "✅ Router scripts installed"

# ------------------------------------------------------------
# Execution & Orchestration
# ------------------------------------------------------------

# 1. Extract the /48 prefix from your constants (e.g., fd89:7a3b:42c0::/48)
# We strip the host ID (::4) and append /48 as required by Asus NVRAM
PROVISION_ULA_VAL := $(shell echo "$(NAS_LAN_IP6)" | sed 's/::[0-9a-fA-F]*$$/::\/48/')

.PHONY: router-ensure-ipv6-ula
router-ensure-ipv6-ula: ensure-default-gateway router-install-provision-ipv6-ula.sh
	@echo "📊 Syncing Router ULA to: $(PROVISION_ULA_VAL)"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
		'DESIRED_ULA_PREFIX="$(PROVISION_ULA_VAL)" $(ROUTER_SCRIPTS)/provision-ipv6-ula.sh'


.PHONY: router-install-ca
router-install-ca:
	@$(INSTALL_PATH)/certs-deploy.sh
#	@ROUTER_CONTROL_PLANE=1 $(INSTALL_PATH)/router-install-ca.sh

export ROUTER_BOOTSTRAP

.PHONY: router-bootstrap
router-bootstrap: export ROUTER_BOOTSTRAP=1
router-bootstrap: ensure-default-gateway \
	router-install-scripts \
	router-ddns \
	router-firewall-install \
	install-ssh-config \
	router-install-ca
	@echo "✅ Router bootstrap complete"

.PHONY: router-all
router-all: ensure-default-gateway \
	router-install-scripts \
	router-firewall-started \
	install-ssh-config
	@echo "🚀 Router base converge complete"

.PHONY: router-all-full
router-all-full: router-all router-caddy install-ssh-config
	@echo "✅ Router and Caddy fully converged"
