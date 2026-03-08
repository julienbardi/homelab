# mk/router/10_bootstrap.mk
# ------------------------------------------------------------
# ROUTER BOOTSTRAP & BASELINE PROVISIONING (namespaced)
# ------------------------------------------------------------

.NOTPARALLEL: \
	router-install-run-as-root \
	router-install-ddns

# Router script sources inside the repository
ROUTER_SCRIPTS_SRC_DIR := $(REPO_ROOT)10.89.12.1/jffs/scripts

# ------------------------------------------------------------
# Router script installation (explicit, one target per script)
# ------------------------------------------------------------

# Base dependency: all scripts require run-as-root.sh to exist first
# (order-only prerequisite)
ROUTER_SCRIPT_BASE := router-install-run-as-root

# --- run-as-root.sh ---------------------------------------------------------
.PHONY: router-install-run-as-root
router-install-run-as-root: | router-ssh-check
	$(INSTALL_FILE_IF_CHANGED) \
		$(ROUTER_SCRIPTS_SRC_DIR)/run-as-root.sh \
		$(ROUTER_SCRIPTS)/run-as-root.sh \
		$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE)

# --- common.sh ---------------------------------------------------------------
.PHONY: router-install-common
router-install-common: | $(ROUTER_SCRIPT_BASE)
	$(INSTALL_FILE_IF_CHANGED) \
		$(ROUTER_SCRIPTS_SRC_DIR)/common.sh \
		$(ROUTER_SCRIPTS)/common.sh \
		$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE)

# --- caddy-reload.sh ---------------------------------------------------------
.PHONY: router-install-caddy-reload
router-install-caddy-reload: | $(ROUTER_SCRIPT_BASE)
	$(INSTALL_FILE_IF_CHANGED) \
		$(ROUTER_SCRIPTS_SRC_DIR)/caddy-reload.sh \
		$(ROUTER_SCRIPTS)/caddy-reload.sh \
		$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE)

# --- certs-create.sh ---------------------------------------------------------
.PHONY: router-install-certs-create
router-install-certs-create: | $(ROUTER_SCRIPT_BASE)
	$(INSTALL_FILE_IF_CHANGED) \
		$(ROUTER_SCRIPTS_SRC_DIR)/certs-create.sh \
		$(ROUTER_SCRIPTS)/certs-create.sh \
		$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE)

# --- certs-deploy.sh ---------------------------------------------------------
.PHONY: router-install-certs-deploy
router-install-certs-deploy: | $(ROUTER_SCRIPT_BASE)
	$(INSTALL_FILE_IF_CHANGED) \
		$(ROUTER_SCRIPTS_SRC_DIR)/certs-deploy.sh \
		$(ROUTER_SCRIPTS)/certs-deploy.sh \
		$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE)

# --- generate-client-cert.sh -------------------------------------------------
.PHONY: router-install-generate-client-cert
router-install-generate-client-cert: | $(ROUTER_SCRIPT_BASE)
	$(INSTALL_FILE_IF_CHANGED) \
		$(ROUTER_SCRIPTS_SRC_DIR)/generate-client-cert.sh \
		$(ROUTER_SCRIPTS)/generate-client-cert.sh \
		$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE)

# --- gen-client-cert-wrapper.sh ---------------------------------------------
.PHONY: router-install-gen-client-cert-wrapper
router-install-gen-client-cert-wrapper: | $(ROUTER_SCRIPT_BASE)
	$(INSTALL_FILE_IF_CHANGED) \
		$(ROUTER_SCRIPTS_SRC_DIR)/gen-client-cert-wrapper.sh \
		$(ROUTER_SCRIPTS)/gen-client-cert-wrapper.sh \
		$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE)

# --- wg-compile-alloc.sh -----------------------------------------------------
.PHONY: router-install-wg-compile-alloc
router-install-wg-compile-alloc: | $(ROUTER_SCRIPT_BASE)
	$(INSTALL_FILE_IF_CHANGED) \
		$(ROUTER_SCRIPTS_SRC_DIR)/wg-compile-alloc.sh \
		$(ROUTER_SCRIPTS)/wg-compile-alloc.sh \
		$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE)

# --- wg-compile-domain.sh ----------------------------------------------------
.PHONY: router-install-wg-compile-domain
router-install-wg-compile-domain: | $(ROUTER_SCRIPT_BASE)
	$(INSTALL_FILE_IF_CHANGED) \
		$(ROUTER_SCRIPTS_SRC_DIR)/wg-compile-domain.sh \
		$(ROUTER_SCRIPTS)/wg-compile-domain.sh \
		$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE)

# --- wg-compile-keys.sh ------------------------------------------------------
.PHONY: router-install-wg-compile-keys
router-install-wg-compile-keys: | $(ROUTER_SCRIPT_BASE)
	$(INSTALL_FILE_IF_CHANGED) \
		$(ROUTER_SCRIPTS_SRC_DIR)/wg-compile-keys.sh \
		$(ROUTER_SCRIPTS)/wg-compile-keys.sh \
		$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE)

# ------------------------------------------------------------
# Install IPv6 ULA provisioning script
# ------------------------------------------------------------
.PHONY: router-install-provision-ipv6-ula
router-install-provision-ipv6-ula: | $(ROUTER_SCRIPT_BASE)
	$(INSTALL_FILE_IF_CHANGED) \
		$(ROUTER_SCRIPTS_SRC_DIR)/provision-ipv6-ula.sh \
		$(ROUTER_SCRIPTS)/provision-ipv6-ula.sh \
		$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE)

# ------------------------------------------------------------
# WireGuard script grouping
# ------------------------------------------------------------
.PHONY: router-wg-install
router-wg-install: \
	router-install-wg-compile-alloc \
	router-install-wg-compile-domain \
	router-install-wg-compile-keys

# ------------------------------------------------------------
# Certificate script grouping
# ------------------------------------------------------------
.PHONY: router-certs-install
router-certs-install: \
	router-install-certs-create \
	router-install-certs-deploy \
	router-install-generate-client-cert \
	router-install-gen-client-cert-wrapper

# ------------------------------------------------------------
# Caddy script grouping
# ------------------------------------------------------------
.PHONY: router-caddy-install
router-caddy-install: \
	router-install-caddy-reload

.PHONY: router-common-install
router-common-install: router-install-common

.PHONY: router-install-scripts
router-install-scripts: \
	router-install-run-as-root \
	router-common-install \
	router-install-common \
	router-wg-install \
	router-certs-install \
	router-caddy-install \
	router-install-provision-ipv6-ula \
	router-install-ddns

# ------------------------------------------------------------
# Install DDNS integration
# ------------------------------------------------------------

# --- ddns-start -------------------------------------------------------------
.PHONY: router-install-ddns
router-install-ddns: | $(ROUTER_SCRIPT_BASE)
	$(INSTALL_FILE_IF_CHANGED) \
		$(ROUTER_SCRIPTS_SRC_DIR)/ddns-start \
		$(ROUTER_SCRIPTS)/ddns-start \
		$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE)

.PHONY: router-ensure-ipv6-ula
router-ensure-ipv6-ula: router-install-provision-ipv6-ula
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '/jffs/scripts/provision-ipv6-ula.sh'

# ------------------------------------------------------------
# Router bootstrap entrypoint (namespaced)
# ------------------------------------------------------------

.PHONY: router-bootstrap
router-bootstrap: \
	router-install-scripts \
	router-install-ddns \
	router-dnsmasq-cache \
	router-firewall-install \
	install-ssh-config
	@echo "✅ Router bootstrap complete"

.PHONY: router-all
router-all: router-install-ddns router-dnsmasq-cache router-firewall-started install-ssh-config
	@echo "🚀 Router base converge complete"

.PHONY: router-all-full
router-all-full: router-all router-caddy install-ssh-config
	@echo "✅ Router and Caddy fully converged"
