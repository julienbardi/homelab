# mk/router/10_bootstrap.mk
# ------------------------------------------------------------
# ROUTER BOOTSTRAP & BASELINE PROVISIONING (namespaced)
# ------------------------------------------------------------

.NOTPARALLEL: \
	router-install-run-as-root \
	router-install-ddns

# Router script sources inside the repository
ROUTER_SCRIPTS_SRC_DIR := $(REPO_ROOT)router/jffs/scripts

# ------------------------------------------------------------
# Internal Macro: Push script to Router via IFC v2
# ------------------------------------------------------------
# Logic: Local Source -> Remote Router (9-argument signature)
# 1: SRC_PATH, 2: DST_PATH
define PUSH_ROUTER_SCRIPT
	{ env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) $(INSTALL_FILE_IF_CHANGED) \
	"" "" $(1) \
	$(ROUTER_HOST) $(ROUTER_SSH_PORT) $(2) \
	$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE) \
	|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; }
endef

.PHONY: router-install-ddns
router-install-ddns: router-install-ddns-start

.PHONY: router-clear-mux
router-clear-mux:
	@rm -f ~/.ssh/cm-*

# Phase Root bootstrap, transport ssh + cat
.PHONY: router-install-run-as-root
router-install-run-as-root: ;

.PHONY: router-bootstrap-run-as-root
router-bootstrap-run-as-root:
	@echo "🛡️  Bootstrapping run-as-root on router"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) 'mkdir -p /jffs/scripts'
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
		'cat > /jffs/scripts/run-as-root' < \
		$(ROUTER_SCRIPTS_SRC_DIR)/run-as-root.sh
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
		'chmod 0755 /jffs/scripts/run-as-root'

# ------------------------------------------------------------
# Router script installation (explicit)
# ------------------------------------------------------------

# Base dependency: all scripts require run-as-root.sh to exist first
ROUTER_SCRIPT_BASE := router-bootstrap-run-as-root

# Authoritative list of router-managed scripts
ROUTER_SCRIPT_FILES := \
	caddy-reload.sh \
	certs-create.sh \
	certs-deploy.sh \
	common.sh \
	ddns-start \
	gen-client-cert-wrapper.sh \
	generate-client-cert.sh \
	provision-ipv6-ula.sh \
	wg-compile-alloc.sh \
	wg-compile-domain.sh \
	wg-compile-keys.sh

.PHONY: router-install-%
router-install-%: | $(ROUTER_SCRIPT_BASE)
	@$(call PUSH_ROUTER_SCRIPT, \
		$(ROUTER_SCRIPTS_SRC_DIR)/$*, \
		$(ROUTER_SCRIPTS)/$*)

ROUTER_INSTALL_TARGETS := $(addprefix router-install-,$(ROUTER_SCRIPT_FILES))

.PHONY: router-install-scripts
router-install-scripts: \
	install-ssh-config \
	router-clear-mux \
	ensure-run-as-root \
	$(INSTALL_FILE_IF_CHANGED) \
	router-install-run-as-root \
	$(ROUTER_INSTALL_TARGETS)
	@echo "✅ Router scripts installed"

# ------------------------------------------------------------
# Execution & Orchestration
# ------------------------------------------------------------

.PHONY: router-ensure-ipv6-ula
router-ensure-ipv6-ula: router-install-provision-ipv6-ula
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '$(ROUTER_SCRIPTS)/provision-ipv6-ula.sh'

.PHONY: router-install-ca
router-install-ca:
	@ROUTER_CONTROL_PLANE=1 $(INSTALL_PATH)/router-install-ca.sh

.PHONY: router-bootstrap
router-bootstrap: \
	router-install-scripts \
	router-install-ddns \
	router-dnsmasq-cache \
	router-firewall-install \
	install-ssh-config \
	router-install-ca
	@echo "✅ Router bootstrap complete"

.PHONY: router-all
router-all: router-install-scripts router-dnsmasq-cache router-firewall-started install-ssh-config
	@echo "🚀 Router base converge complete"

.PHONY: router-all-full
router-all-full: router-all router-caddy install-ssh-config
	@echo "✅ Router and Caddy fully converged"