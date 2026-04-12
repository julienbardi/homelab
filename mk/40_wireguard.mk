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

.PHONY: \
	wg-clean-out \
	wg-generate \
	wg-install-router \
	wg-install-nas \
	wg-up-router \
	wg-up-nas \
	wg-down-router \
	wg-down-nas \
	wg-status \
	wg-up \
	wg-down \
	router-ensure-wg-module \
	wg-router-preflight

run_as_root_router = ssh -p 2222 julie@10.89.12.1

# Ensure WireGuard kernel module loads at boot
router-ensure-wg-module:
	@ssh -p 2222 julie@$(ROUTER_IP) '\
		touch /jffs/scripts/services-start; \
		chmod 0755 /jffs/scripts/services-start; \
		if ! grep -q "modprobe wireguard" /jffs/scripts/services-start; then \
			echo "modprobe wireguard" >> /jffs/scripts/services-start; \
		fi \
	'


# Ensure WireGuard kernel module is loaded on the router
wg-router-preflight:
	@$(run_as_root_router) modprobe wireguard || true


# We use the global install_script macro to handle Exit Code 3 correctly.
define PUSH_WG_SCRIPT
	$(call install_script,$(1),$(notdir $(2)))
endef

# ------------------------------------------------------------
# Install edges (repo -> $(INSTALL_PATH))
# ------------------------------------------------------------

# Define both required scripts explicitly
$(INSTALL_PATH)/wgctl.sh: $(REPO_ROOT)scripts/wgctl.sh | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

$(INSTALL_PATH)/wg-generate-configs.sh: $(REPO_ROOT)scripts/wg-generate-configs.sh | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

wg-clean-out: wg-down-router wg-down-nas ensure-run-as-root
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🧹 cleaning WireGuard"; fi
	@$(run_as_root) rm -f \
		"$(INSTALL_PATH)/wgctl.sh" \
		"$(INSTALL_PATH)/wg-generate-configs.sh"

# ------------------------------------------------------------
# GENERATION (Depends on scripts being present)
# ------------------------------------------------------------
# Note: $(INSTALL_PATH)/wg-generate-configs.sh is a file target,
# so wg-generate is now safely guarded.
wg-generate: $(INSTALL_PATH)/wg-generate-configs.sh
	@$(INSTALL_PATH)/wg-generate-configs.sh

# ------------------------------------------------------------
# INSTALLATION (Strictly depends on generation finishing)
# ------------------------------------------------------------
# We keep these separate to allow 'make wg-install-nas' without touching the router.

wg-install-router:  router-wireguard-enable wg-router-preflight $(INSTALL_PATH)/wgctl.sh wg-generate
	@ROUTER_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh router install

wg-install-nas: $(INSTALL_PATH)/wgctl.sh wg-generate
	@NAS_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh nas install

# ------------------------------------------------------------
# BRING-UP / TEARDOWN
# ------------------------------------------------------------

wg-up-router: wg-router-preflight wg-install-router
	@ROUTER_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh router up

# NAS now waits for the Router to be fully UP
wg-up-nas: wg-install-nas wg-up-router
	@NAS_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh nas up

# NAS goes down first
wg-down-nas: $(INSTALL_PATH)/wgctl.sh
	@NAS_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh nas down

# Router waits for NAS to disconnect (Sequential Teardown)
wg-down-router: wg-router-preflight $(INSTALL_PATH)/wgctl.sh wg-down-nas
	@ROUTER_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh router down

# ------------------------------------------------------------
# STATUS
# ------------------------------------------------------------

wg-status: wg-router-preflight $(INSTALL_PATH)/wgctl.sh
	@ROUTER_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh router status || true
	@NAS_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh nas status || true

# ------------------------------------------------------------
# FULL CONVERGENCE
# ------------------------------------------------------------

wg-up: wg-up-nas
	@echo "🚀 WireGuard fully converged"

wg-down: wg-down-router
	@echo "🛑 WireGuard fully stopped"