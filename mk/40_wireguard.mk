# mk/40_wireguard.mk — WireGuard Control Plane
# Orchestrates lifecycle (intent → gen → deploy → up) for NAS & Router.

WG_OUTPUT_ROUTER := $(WG_ROOT)/output/router

WG_FIREWALL := $(WG_OUTPUT_ROUTER)/wg-firewall.sh

.PHONY: \
	wg-clean-out wg-generate wg-install-router wg-install-nas \
	wg-up-nas wg-down-router wg-down-nas \
	wg-status wg-up wg-down router-ensure-wg-module \
	router-wg-health-strict router-wg-audit \
	wg-clean-state

ACTUAL_USER := $(or $(SUDO_USER),$(USER))
# Capture the user context
# DDA-Compliant: Resolve home directory via system database instead of hardcoded paths
ACTUAL_HOME := $(or \
	$(shell getent passwd $(ACTUAL_USER) | cut -d: -f6), \
	$(HOME) \
)

export ROUTER_IDENTITY := $(ACTUAL_HOME)/.ssh/id_ed25519

# SSH Multiplexing Config
SSH_SOCK_FILE := /tmp/ssh-$(ACTUAL_USER)-router-$(ROUTER_SSH_PORT)

# Canonical environment block for router/NAS control-plane operations
WG_ENV = \
	ROUTER_HOST="$(ROUTER_HOST)" \
	ROUTER_SSH_PORT="$(ROUTER_SSH_PORT)" \
	ROUTER_WG_DIR="$(ROUTER_WG_DIR)" \
	WG_ROOT="$(WG_ROOT)"

# Define the unified sudo wrapper for homelab root operations
# This ensures Root inherits Julie's SSH tunnel and identity context
WG_SUDO := sudo --preserve-env=ROUTER_HOST,ROUTER_ADDR,ROUTER_SSH_PORT,ROUTER_WG_DIR,WG_ROOT,WG_SUBNETS_MK,SSH_AUTH_SOCK,ROUTER_IDENTITY,SSH_CONTROL_PATH

run_as_root_router := ssh -p $(ROUTER_SSH_PORT) \
	-o ControlMaster=auto \
	-o ControlPath=$(SSH_SOCK_FILE) \
	-o ControlPersist=60s \
	-o BatchMode=yes \
	-o IdentityFile=$(ROUTER_IDENTITY) \
	-o StrictHostKeyChecking=accept-new \
	$(ROUTER_HOST)

WG_SUBNETS_MK := $(SYSTEM_STATE_DIR)/wg-subnets.mk

# --------------------------------------------------------------------
# Generated subnet map (router + NAS WG subnets)
# --------------------------------------------------------------------

$(WG_SUBNETS_MK): $(WG_ROOT)/input/wg-interfaces.tsv $(INSTALL_PATH)/wg-plan-subnets.sh | ensure-stamp-dir
	@echo "🌐 Generating WireGuard subnet map"
	@WG_ROOT="$(WG_ROOT)" WG_SUBNETS_MK="$(WG_SUBNETS_MK)" \
	  $(WG_SUDO) $(INSTALL_PATH)/wg-plan-subnets.sh

# Load the generated subnet map into the DAG (optional: tolerate first-run absence)
-include $(WG_SUBNETS_MK)

wg-generate: $(WG_SUBNETS_MK) router-bootstrap-wg-keys $(INSTALL_PATH)/wg-generate-configs.sh
	@DNS_TOPDOMAIN_NAME="$$( $(WITH_SECRETS) sh -c 'echo "$$ddns_topdomain"' )" \
	NAS_LAN_IP=$(NAS_LAN_IP) NAS_LAN_IP6=$(NAS_LAN_IP6) WG_ROOT=$(WG_ROOT) \
	$(INSTALL_PATH)/wg-generate-configs.sh

wg-clean-state:
	@$(WG_SUDO) rm -f $(WG_SUBNETS_MK)

# --- Router Setup ---

router-ensure-wg-module: router-install-scripts
	@if [ -z "$(ROUTER_WG_DIR)" ]; then echo "ERROR: ROUTER_WG_DIR undefined"; exit 1; fi
	@echo "🛡️ [router] Ensuring WireGuard kernel module on $(ROUTER_ADDR):$(ROUTER_SSH_PORT)..."

.PHONY: router-bootstrap-wg-keys
router-bootstrap-wg-keys:
	@echo "🧬 [router] Ensuring WireGuard identity in NVRAM (wgs1)..."
	@$(run_as_root_router) ' \
		set -eu; \
		priv="$$(nvram get wgs1_priv 2>/dev/null || true)"; \
		pub="$$(nvram get wgs1_pub 2>/dev/null || true)"; \
		if [ -n "$$priv" ] && [ -n "$$pub" ]; then \
			echo "🔒 Existing WireGuard identity found in NVRAM (wgs1)."; \
			exit 0; \
		fi; \
		echo "🔐 Generating new WireGuard identity for wgs1 in NVRAM..."; \
		wgs1_priv="$$(wg genkey)"; \
		wgs1_pub="$$(printf '%s' "$$wgs1_priv" | wg pubkey)";
		nvram set wgs1_priv="$$wgs1_priv"; \
		nvram set wgs1_pub="$$wgs1_pub"; \
		nvram commit; \
		unset wgs1_priv wgs1_pub; \
		echo "✅ Router WireGuard identity stored in NVRAM (wgs1_priv / wgs1_pub)."; \
	'

# --- File Operations ---

define PUSH_WG_SCRIPT
	$(call install_script,$(1),$(notdir $(2)))
endef

$(INSTALL_PATH)/wgctl.sh: $(REPO_ROOT)/scripts/wgctl.sh | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

$(INSTALL_PATH)/wg-generate-configs.sh: $(REPO_ROOT)/scripts/wg-generate-configs.sh | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

wg-clean-out: wg-down-router wg-down-nas wg-clean-state
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🧹 Cleaning local scripts & SSH sockets"; fi
	@sudo rm -f "$(INSTALL_PATH)/wgctl.sh" "$(INSTALL_PATH)/wg-generate-configs.sh"
	@rm -f $(SSH_SOCK_FILE)
	@echo "🧹 Cleaning remote router scripts"
	@$(run_as_root_router) "rm -f $(ROUTER_SCRIPTS)/wg-firewall.sh"

# --- Deployment --

router-firewall: wg-generate
	@echo "🛡️ [router] Installing firewall for WireGuard..."

	$(call TMPFILE_BLOCK,"$(TMP_ROUTER_WG_FIREWALL)", \
		umask 077; \
		trap 'rm -f "$(TMP_ROUTER_WG_FIREWALL)"' EXIT; \
		cat "$(WG_FIREWALL)" > "$(TMP_ROUTER_WG_FIREWALL)"; \

		FEC=0; \
		SSH_CONTROL_PATH="$(SSH_SOCK_FILE)" \
		$(INSTALL_FILE_IF_CHANGED) "-q" \
			"" "" "$(TMP_ROUTER_WG_FIREWALL)" \
			"$(ROUTER_HOST)" $(ROUTER_SSH_PORT) "$(ROUTER_SCRIPTS)/wg-firewall.sh" \
			"0" "0" "0755" || FEC=$$?; \
		if [ "$$FEC" != "0" ] && [ "$$FEC" != "3" ]; then exit "$$FEC"; fi; \
		if [ "$$FEC" = "0" ]; then \
			$(run_as_root_router) "$(ROUTER_SCRIPTS)/wg-firewall.sh" || true; \
		fi
	)

wg-install-router: router-ensure-wg-module \
	$(INSTALL_PATH)/wgctl.sh wg-generate $(INSTALL_FILE_IF_CHANGED) router-firewall
	@EC=0; \
	SSH_CONTROL_PATH="$(SSH_SOCK_FILE)" \
	$(WG_ENV) \
	ROUTER_CONTROL_PLANE=1 \
	$(INSTALL_PATH)/wgctl.sh router install-up || EC=$$?; \
	if [ "$$EC" != "0" ] && [ "$$EC" != "3" ]; then exit "$$EC"; fi

wg-install-nas: $(INSTALL_PATH)/wgctl.sh $(INSTALL_FILE_IF_CHANGED)
	@echo "📦 [nas   ] Installing WireGuard configurations..."
	@EC=0; \
	$(WG_ENV) \
	NAS_CONTROL_PLANE=1 \
	$(WG_SUDO) $(INSTALL_PATH)/wgctl.sh nas install-up || EC=$$?; \
	if [ "$$EC" != "0" ] && [ "$$EC" != "3" ]; then exit "$$EC"; fi

# --- Lifecycle Management ---

wg-up-nas: wg-install-nas
	@true

wg-down-nas: $(INSTALL_PATH)/wgctl.sh
	@$(WG_SUDO) \
	$(WG_ENV) \
	NAS_CONTROL_PLANE=1 \
	$(INSTALL_PATH)/wgctl.sh nas down

wg-down-router: wg-down-nas
	@SSH_CONTROL_PATH="$(SSH_SOCK_FILE)" \
	$(WG_ENV) \
	ROUTER_CONTROL_PLANE=1 \
	$(INSTALL_PATH)/wgctl.sh router down

wg-status: $(INSTALL_PATH)/wgctl.sh
	@$(WG_ENV) \
	ROUTER_CONTROL_PLANE=1 \
	$(INSTALL_PATH)/wgctl.sh router status || true
	@$(WG_ENV) \
	NAS_CONTROL_PLANE=1 \
	$(INSTALL_PATH)/wgctl.sh nas status || true

wg-up: wg-install-router wg-up-nas
	@echo "🚀 WireGuard fully converged"

wg-down: wg-down-router
	@echo "✅ WireGuard fully stopped"

router-wg-health-strict:
	@echo "🔍 Strict WireGuard health check on router"
	@$(run_as_root_router) 'set -e; \
		if ! wg show wgs1 >/dev/null 2>&1; then \
			echo "❌ WireGuard interface wgs1 missing or down"; \
			exit 1; \
		fi; \
		echo "🟢 WireGuard interface wgs1 present"; \
	'

router-wg-audit:
	@echo "🔍 Auditing WireGuard configuration on router"
	@$(run_as_root_router) 'set -e; \
		echo "📝 WireGuard interfaces:"; \
		wg show; \
		echo "📝 Routing table:"; \
		ip route show table all | grep -E "wgs1|wg"; \
	'
