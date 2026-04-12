# mk/40_wireguard.mk
# ------------------------------------------------------------
# WIREGUARD CONTROL PLANE
# ------------------------------------------------------------
#
# Purpose:
#   Full WireGuard lifecycle:
#     - intent → generation
#     - generation → deployment
#     - deployment → bring-up
#
# Scope:
#   - NAS + router orchestration
#   - No inline business logic
#
# Ownership:
#   - All stateful behavior lives in scripts/ and router/jffs/scripts/
#   - This file is orchestration + DAG only
#
# Contracts:
#   - MUST NOT invoke $(MAKE)
#   - MUST be correct under 'make -j'
#   - MUST NOT rely on timestamps for remote state
#
# ------------------------------------------------------------

WG_SCRIPTS_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../scripts)

# We use the global install_script macro to handle Exit Code 3 correctly.
define PUSH_WG_SCRIPT
	$(call install_script,$(1),$(notdir $(2)))
endef

# ---------------------------------------------------------------------------
# Script Path Definitions
# ---------------------------------------------------------------------------
WGCTL_SCRIPT := $(WG_SCRIPTS_ROOT)/wgctl.sh

WG_INSTALL_SOURCES := \
	$(WG_SCRIPTS_ROOT)/wgctl.sh \
	$(WG_SCRIPTS_ROOT)/wg-generate-configs.sh

# ---------------------------------------------------------------------------
# Install edges (repo -> $(INSTALL_PATH))
# ---------------------------------------------------------------------------

$(INSTALL_PATH)/wgctl.sh: $(WG_SCRIPTS_ROOT)/wgctl.sh | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

.PHONY: wg-install-scripts wg-clean-out wg-validate-input wg-contract-check

wg-install-scripts: install-all \
	$(INSTALL_PATH)/wgctl.sh \
	$(INSTALL_PATH)/wg-generate-configs.sh
	@true

wg-clean-out: wg-down-router wg-down-nas ensure-run-as-root
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🧹 cleaning WireGuard"; fi
	@$(run_as_root) rm -rf \
		"$(INSTALL_PATH)/wgctl.sh" 
		"$(INSTALL_PATH)/wg-generate-configs.sh

wg-contract-check:
	@$(foreach s,$(WG_INSTALL_SOURCES), test -x "$(s)" || { echo "❌ Script not executable: $(s)"; exit 1; } ;)
	@echo "✅ WireGuard build contract holds"

# ------------------------------------------------------------
# GENERATION
# ------------------------------------------------------------

.PHONY: wg-generate
wg-generate: wg-install-scripts
	@$(INSTALL_PATH)/wg-generate-configs.sh

# ------------------------------------------------------------
# INSTALLATION
# ------------------------------------------------------------

.PHONY: wg-install-router
wg-install-router: $(INSTALL_PATH)/wgctl.sh
	@ROUTER_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh router install

.PHONY: wg-install-nas
wg-install-nas: $(INSTALL_PATH)/wgctl.sh
	@NAS_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh nas install

# ------------------------------------------------------------
# BRING-UP / TEARDOWN
# ------------------------------------------------------------

.PHONY: wg-up-router
wg-up-router: $(INSTALL_PATH)/wgctl.sh
	@ROUTER_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh router up

.PHONY: wg-up-nas
wg-up-nas: $(INSTALL_PATH)/wgctl.sh
	@NAS_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh nas up

.PHONY: wg-down-router
wg-down-router: $(INSTALL_PATH)/wgctl.sh
	@ROUTER_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh router down

.PHONY: wg-down-nas
wg-down-nas: $(INSTALL_PATH)/wgctl.sh
	@NAS_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh nas down

# ------------------------------------------------------------
# STATUS
# ------------------------------------------------------------

.PHONY: wg-status
wg-status:
	@ROUTER_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh router status || true
	@NAS_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh nas status || true

# ------------------------------------------------------------
# FULL CONVERGENCE
# ------------------------------------------------------------

.PHONY: wg-up
wg-up: wg-generate wg-install-router wg-install-nas wg-up-router wg-up-nas
	@echo "🚀 WireGuard fully converged"

.PHONY: wg-down
wg-down: wg-down-router wg-down-nas
	@echo "🛑 WireGuard fully stopped"
