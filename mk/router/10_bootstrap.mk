# ============================================================
# mk/router/10_bootstrap.mk
# ============================================================
# ROUTER BOOTSTRAP & BASELINE PROVISIONING (namespaced)
# ------------------------------------------------------------

.NOTPARALLEL: \
	router-install-run-as-root \
	router-install-ddns

# ------------------------------------------------------------
# Local Tooling: IFC engine (File-based dependencies)
# ------------------------------------------------------------

# Authoritative local paths (Sync with mk/01_common.mk)
IFC_V2_BIN        := /usr/local/bin/install_file_if_changed_v2.sh
IFC_V2_PLURAL_BIN := /usr/local/bin/install_files_if_changed_v2.sh

# Grouping target for local tools (Phony)
# Recipes are defined in mk/01_common.mk
.PHONY: install-local-ifc-engine
install-local-ifc-engine:  $(IFC_V2_BIN) $(IFC_V2_PLURAL_BIN)

# Update the base dependency to ensure the engine is present before any push
router-install-scripts: ensure-run-as-root install-local-ifc-engine

# Router script sources inside the repository
ROUTER_SCRIPTS_SRC_DIR := $(REPO_ROOT)10.89.12.1/jffs/scripts

# ------------------------------------------------------------
# Internal Macro: Push script to Router via IFC v2
# ------------------------------------------------------------
# Logic: Local Source -> Remote Router (9-argument signature)
# 1: SRC_PATH, 2: DST_PATH
define PUSH_ROUTER_SCRIPT
	env CHANGED_EXIT_CODE=0 $(IFC_V2_BIN) \
	"" "" $(1) \
	$(ROUTER_HOST) $(ROUTER_SSH_PORT) $(2) \
	$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE)
endef

.PHONY: router-clear-mux
router-clear-mux:
	rm -f ~/.ssh/cm-*

# ------------------------------------------------------------
# Router script installation (explicit)
# ------------------------------------------------------------

# Base dependency: all scripts require run-as-root.sh to exist first
ROUTER_SCRIPT_BASE := router-install-run-as-root

# --- run-as-root.sh ---------------------------------------------------------
# Note: The local /usr/local/sbin/run-as-root.sh is managed by mk/01_common.mk
.PHONY: router-install-run-as-root
router-install-run-as-root: $(IFC_V2_BIN) | install-ssh-config router-clear-mux router-ssh-check
	@$(call PUSH_ROUTER_SCRIPT,$(ROUTER_SCRIPTS_SRC_DIR)/run-as-root.sh,$(ROUTER_SCRIPTS)/run-as-root.sh)

# --- install_file_if_changed_v2.sh (Singular) --------------------------------
.PHONY: router-install-ifc-v2
router-install-ifc-v2: | $(ROUTER_SCRIPT_BASE)
	@$(call PUSH_ROUTER_SCRIPT,$(MAKEFILE_DIR)scripts/install_file_if_changed_v2.sh,$(ROUTER_SCRIPTS)/install_file_if_changed_v2.sh)

# --- install_files_if_changed_v2.sh (Plural) ---------------------------------
.PHONY: router-install-ifc-v2-plural
router-install-ifc-v2-plural: | $(ROUTER_SCRIPT_BASE)
	@$(call PUSH_ROUTER_SCRIPT,$(MAKEFILE_DIR)scripts/install_files_if_changed_v2.sh,$(ROUTER_SCRIPTS)/install_files_if_changed_v2.sh)

# --- common.sh ---------------------------------------------------------------
.PHONY: router-install-common
router-install-common: | $(ROUTER_SCRIPT_BASE)
	@$(call PUSH_ROUTER_SCRIPT,$(ROUTER_SCRIPTS_SRC_DIR)/common.sh,$(ROUTER_SCRIPTS)/common.sh)

# --- caddy-reload.sh ---------------------------------------------------------
.PHONY: router-install-caddy-reload
router-install-caddy-reload: | $(ROUTER_SCRIPT_BASE)
	@$(call PUSH_ROUTER_SCRIPT,$(ROUTER_SCRIPTS_SRC_DIR)/caddy-reload.sh,$(ROUTER_SCRIPTS)/caddy-reload.sh)

# --- certs-create.sh ---------------------------------------------------------
.PHONY: router-install-certs-create
router-install-certs-create: | $(ROUTER_SCRIPT_BASE)
	@$(call PUSH_ROUTER_SCRIPT,$(ROUTER_SCRIPTS_SRC_DIR)/certs-create.sh,$(ROUTER_SCRIPTS)/certs-create.sh)

# --- certs-deploy.sh ---------------------------------------------------------
.PHONY: router-install-certs-deploy
router-install-certs-deploy: | $(ROUTER_SCRIPT_BASE)
	@$(call PUSH_ROUTER_SCRIPT,$(ROUTER_SCRIPTS_SRC_DIR)/certs-deploy.sh,$(ROUTER_SCRIPTS)/certs-deploy.sh)

# --- generate-client-cert.sh -------------------------------------------------
.PHONY: router-install-generate-client-cert
router-install-generate-client-cert: | $(ROUTER_SCRIPT_BASE)
	@$(call PUSH_ROUTER_SCRIPT,$(ROUTER_SCRIPTS_SRC_DIR)/generate-client-cert.sh,$(ROUTER_SCRIPTS)/generate-client-cert.sh)

# --- gen-client-cert-wrapper.sh ---------------------------------------------
.PHONY: router-install-gen-client-cert-wrapper
router-install-gen-client-cert-wrapper: | $(ROUTER_SCRIPT_BASE)
	@$(call PUSH_ROUTER_SCRIPT,$(ROUTER_SCRIPTS_SRC_DIR)/gen-client-cert-wrapper.sh,$(ROUTER_SCRIPTS)/gen-client-cert-wrapper.sh)

# --- wg-compile-alloc.sh -----------------------------------------------------
.PHONY: router-install-wg-compile-alloc
router-install-wg-compile-alloc: | $(ROUTER_SCRIPT_BASE)
	@$(call PUSH_ROUTER_SCRIPT,$(ROUTER_SCRIPTS_SRC_DIR)/wg-compile-alloc.sh,$(ROUTER_SCRIPTS)/wg-compile-alloc.sh)

# --- wg-compile-domain.sh ----------------------------------------------------
.PHONY: router-install-wg-compile-domain
router-install-wg-compile-domain: | $(ROUTER_SCRIPT_BASE)
	@$(call PUSH_ROUTER_SCRIPT,$(ROUTER_SCRIPTS_SRC_DIR)/wg-compile-domain.sh,$(ROUTER_SCRIPTS)/wg-compile-domain.sh)

# --- wg-compile-keys.sh ------------------------------------------------------
.PHONY: router-install-wg-compile-keys
router-install-wg-compile-keys: | $(ROUTER_SCRIPT_BASE)
	@$(call PUSH_ROUTER_SCRIPT,$(ROUTER_SCRIPTS_SRC_DIR)/wg-compile-keys.sh,$(ROUTER_SCRIPTS)/wg-compile-keys.sh)

# --- provision-ipv6-ula.sh --------------------------------------------------
.PHONY: router-install-provision-ipv6-ula
router-install-provision-ipv6-ula: | $(ROUTER_SCRIPT_BASE)
	@$(call PUSH_ROUTER_SCRIPT,$(ROUTER_SCRIPTS_SRC_DIR)/provision-ipv6-ula.sh,$(ROUTER_SCRIPTS)/provision-ipv6-ula.sh)

# --- ddns-start -------------------------------------------------------------
.PHONY: router-install-ddns
router-install-ddns: | $(ROUTER_SCRIPT_BASE)
	@$(call PUSH_ROUTER_SCRIPT,$(ROUTER_SCRIPTS_SRC_DIR)/ddns-start,$(ROUTER_SCRIPTS)/ddns-start)

# ------------------------------------------------------------
# Grouping Targets
# ------------------------------------------------------------

.PHONY: router-engine-install
router-engine-install: \
	router-install-ifc-v2 \
	router-install-ifc-v2-plural

.PHONY: router-wg-install
router-wg-install: \
	router-install-wg-compile-alloc \
	router-install-wg-compile-domain \
	router-install-wg-compile-keys

.PHONY: router-certs-install
router-certs-install: \
	router-install-certs-create \
	router-install-certs-deploy \
	router-install-generate-client-cert \
	router-install-gen-client-cert-wrapper

.PHONY: router-caddy-install
router-caddy-install: \
	router-install-caddy-reload

.PHONY: router-common-install
router-common-install: router-install-common

.PHONY: router-install-scripts
router-install-scripts: install-ssh-config router-clear-mux \
	ensure-run-as-root \
	install-local-ifc-engine \
	router-install-run-as-root \
	router-engine-install \
	router-common-install \
	router-wg-install \
	router-certs-install \
	router-caddy-install \
	router-install-provision-ipv6-ula \
	router-install-ddns

# ------------------------------------------------------------
# Execution & Orchestration
# ------------------------------------------------------------

.PHONY: router-ensure-ipv6-ula
router-ensure-ipv6-ula: router-install-provision-ipv6-ula
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '$(ROUTER_SCRIPTS)/provision-ipv6-ula.sh'

.PHONY: router-bootstrap
router-bootstrap: \
	router-install-scripts \
	router-install-ddns \
	router-dnsmasq-cache \
	router-firewall-install \
	install-ssh-config
	@echo "✅ Router bootstrap complete"

.PHONY: router-all
router-all: router-install-scripts router-dnsmasq-cache router-firewall-started install-ssh-config
	@echo "🚀 Router base converge complete"

.PHONY: router-all-full
router-all-full: router-all router-caddy install-ssh-config
	@echo "✅ Router and Caddy fully converged"