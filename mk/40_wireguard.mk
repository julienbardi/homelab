# mk/40_wireguard.mk — WireGuard Control Plane
# Orchestrates lifecycle (intent → gen → deploy → up) for NAS & Router.
# Logic lives in scripts/; this file manages the DAG only.
# Contract: No $(MAKE) calls, 'make -j' safe, no remote timestamp reliance.

.PHONY: \
	wg-clean-out wg-generate wg-install-router wg-install-nas \
	wg-up-router wg-up-nas wg-down-router wg-down-nas \
	wg-status wg-up wg-down router-ensure-wg-module wg-router-preflight

# Authoritative SSH command using 00_constants.mk
run_as_root_router := ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST)

# Persist module load on boot
router-ensure-wg-module:
	@if [ -z "$(ROUTER_WG_DIR)" ]; then echo "ERROR: ROUTER_WG_DIR undefined"; exit 1; fi
	@$(run_as_root_router) "mkdir -p $(ROUTER_WG_DIR) && touch $(ROUTER_SCRIPTS)/services-start && chmod 0755 $(ROUTER_SCRIPTS)/services-start && (grep -q 'modprobe wireguard' $(ROUTER_SCRIPTS)/services-start || echo 'modprobe wireguard' >> $(ROUTER_SCRIPTS)/services-start)"

# Immediate module load
wg-router-preflight:
	@$(run_as_root_router) modprobe wireguard || true

define PUSH_WG_SCRIPT
	$(call install_script,$(1),$(notdir $(2)))
endef

# --- Edges (Repo -> Bin) ---

$(INSTALL_PATH)/wgctl.sh: $(REPO_ROOT)scripts/wgctl.sh | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

$(INSTALL_PATH)/wg-generate-configs.sh: $(REPO_ROOT)scripts/wg-generate-configs.sh | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

# SAFETY: Cleanup requires BOTH sides down. Explicit NAS dep prevents unsafe race conditions.
wg-clean-out: wg-down-router wg-down-nas ensure-run-as-root
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🧹 cleaning WireGuard"; fi
	@$(run_as_root) rm -f "$(INSTALL_PATH)/wgctl.sh" "$(INSTALL_PATH)/wg-generate-configs.sh"

# --- DAG ---

wg-generate: $(INSTALL_PATH)/wg-generate-configs.sh
	@$(INSTALL_PATH)/wg-generate-configs.sh

wg-install-router: router-ensure-wg-module wg-router-preflight $(INSTALL_PATH)/wgctl.sh wg-generate
	@set -e; \
	EC=0; \
	ROUTER_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh router install || EC=$$?; \
	if [ "$$EC" != "0" ] && [ "$$EC" != "3" ]; then exit "$$EC"; fi
	@if [ -f "$(OUTPUT_ROUTER)/wgs1.firewall.sh" ]; then \
		echo "🛡️ [wg-install-router] Syncing firewall rules to router"; \
		{ \
			echo "set -e;"; \
			echo "iptables -S FORWARD | grep 'wgs1' | sed 's/-A/-D/' | while read line; do iptables \$$line 2>/dev/null || true; done"; \
			cat "$(OUTPUT_ROUTER)/wgs1.firewall.sh"; \
		} | $(run_as_root_router) "bash -s"; \
	fi

# NAS WireGuard Installation (Privileged)
wg-install-nas: router-require-run-as-root | $(STAMP_DIR)
	@echo "📦 Installing WireGuard configs on NAS"
	@$(run_as_root) sh -c '\
		ROUTER_HOST="$(ROUTER_HOST)" \
		ROUTER_SSH_PORT="$(ROUTER_SSH_PORT)" \
		ROUTER_WG_DIR="$(ROUTER_WG_DIR)" \
		WG_ROOT="$(WG_ROOT)" \
		$(INSTALL_PATH)/wgctl.sh nas install \
	'

wg-up-router: wg-install-router
	@ROUTER_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh router up

# Sequential Bring-up: Router gateway must be UP for NAS client handshake.
wg-up-nas: wg-install-nas wg-up-router
	@NAS_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh nas up

wg-down-nas: $(INSTALL_PATH)/wgctl.sh
	@NAS_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh nas down

# Sequential Teardown: Router waits for NAS to drop to prevent gateway orphan sessions.
wg-down-router: wg-down-nas
	@ROUTER_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh router down

wg-status: $(INSTALL_PATH)/wgctl.sh
	@ROUTER_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh router status || true
	@NAS_CONTROL_PLANE=1 $(INSTALL_PATH)/wgctl.sh nas status || true

wg-up: wg-up-nas
	@echo "🚀 WireGuard fully converged"

wg-down: wg-down-router
	@echo "❌ WireGuard fully stopped"