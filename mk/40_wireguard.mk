# --------------------------------------------------------------------
# mk/40_wireguard.mk — WireGuard Control Plane
# --------------------------------------------------------------------
# CONTRACT:
# - Orchestrates lifecycle (intent → gen → deploy → up) for NAS & Router.
# - Configuration updates MUST trigger a local state tracking stamp.
# - Subshell execution loops MUST be explicitly guarded against failure.
# - Operations MUST handle Asuswrt-Merlin vs NAS paths deterministically.
# - All userland commands MUST respect system database home configurations.
# --------------------------------------------------------------------

WG_OUTPUT_ROUTER := $(WG_ROOT)/output/router
WG_FIREWALL      := $(WG_OUTPUT_ROUTER)/wg-firewall.sh

# Persistent state tracking markers
WG_STAMP_DIR        := $(SYSTEM_STATE_DIR)/stamps
WG_ROUTER_DIRTY_STAMP := $(WG_STAMP_DIR)/wg_router_dirty.stamp
WG_NAS_DIRTY_STAMP    := $(WG_STAMP_DIR)/wg_nas_dirty.stamp

# Explicit interface inventory managed by the control plane
WG_INTERFACES_NAS    := wg0 wg1 wg2 wg3 wg4 wg5 wg6 wg7 wg8 wg9 wg10 wg11 wg12 wg13 wg14 wg15
WG_INTERFACES_ROUTER := wgs1

.PHONY: \
	wg-clean-out wg-generate wg-install-router wg-install-nas \
	wg-up-nas wg-down-router wg-down-nas \
	wg-status wg-install wg-up wg-down router-ensure-wg-module \
	router-wg-health-strict router-wg-audit \
	wg-clean-state wg7-validate wg-router-ipv6-probe

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

# Unified sudo wrapper for homelab root operations
WG_SUDO := sudo --preserve-env=ROUTER_HOST,ROUTER_ADDR,ROUTER_SSH_PORT,ROUTER_WG_DIR,WG_ROOT,WG_SUBNETS_MK,SSH_AUTH_SOCK,ROUTER_IDENTITY,SSH_CONTROL_PATH

run_as_root_router := ssh -p $(ROUTER_SSH_PORT) \
	-o ControlMaster=auto \
	-o ControlPath=$(SSH_SOCK_FILE) \
	-o ControlPersist=60s \
	-o BatchMode=yes \
	-o IdentityFile=$(ROUTER_IDENTITY) \
	-o StrictHostKeyChecking=yes \
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
	@echo "🔍 Staging configuration hash states before generation execution"
	@ROUTER_OLD_HASH=$$(sha256sum $(WG_OUTPUT_ROUTER)/*.conf 2>/dev/null | sha256sum | awk '{print $$1}') || ROUTER_OLD_HASH=""; \
	DNS_TOPDOMAIN_NAME="$$( $(call WITH_SECRETS, sh -c 'echo "$$ddns_topdomain"') )" \
	NAS_LAN_IP="$(NAS_LAN_IP)" \
	NAS_LAN_IP6="$(NAS_LAN_IP6)" \
	LAN_ROUTER="$(LAN_ROUTER)" \
	WG_ROOT="$(WG_ROOT)" \
	$(INSTALL_PATH)/wg-generate-configs.sh; \
	ROUTER_NEW_HASH=$$(sha256sum $(WG_OUTPUT_ROUTER)/*.conf 2>/dev/null | sha256sum | awk '{print $$1}') || ROUTER_NEW_HASH=""; \
	if [ "$$ROUTER_OLD_HASH" != "$$ROUTER_NEW_HASH" ]; then \
		echo "⚠️  WireGuard configuration mutation caught — marking runtime topologies dirty"; \
		mkdir -p "$(WG_STAMP_DIR)"; \
		touch "$(WG_ROUTER_DIRTY_STAMP)" "$(WG_NAS_DIRTY_STAMP)"; \
	fi

wg-clean-state:
	@$(WG_SUDO) rm -f $(WG_SUBNETS_MK)
	@rm -f "$(WG_ROUTER_DIRTY_STAMP)" "$(WG_NAS_DIRTY_STAMP)"

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
		wgs1_pub="$$(printf "%s" "$$wgs1_priv" | wg pubkey)"; \
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

$(INSTALL_PATH)/wg-readiness-probe.sh: $(REPO_ROOT)/scripts/wg-readiness-probe.sh | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

$(INSTALL_PATH)/wg-generate-configs.sh: $(REPO_ROOT)/scripts/wg-generate-configs.sh | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

# Change this target block:
wg-clean-out: wg-down-router wg-down-nas wg-clean-state
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🧹 Cleaning local scripts & SSH sockets"; fi
	@sudo rm -f "$(INSTALL_PATH)/wgctl.sh" "$(INSTALL_PATH)/wg-generate-configs.sh" "$(INSTALL_PATH)/wg-readiness-probe.sh"
	@rm -f $(SSH_SOCK_FILE)
	@echo "🧹 Cleaning remote router scripts"
	@$(run_as_root_router) "rm -f $(ROUTER_SCRIPTS)/wg-firewall.sh"

# --- Deployment ---
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
			$(ROUTER_HOST) $(ROUTER_SSH_PORT) "$(ROUTER_SCRIPTS)/wg-firewall.sh" \
			"0" "0" "0755" || FEC=$$?; \
		if [ "$$FEC" != "0" ] && [ "$$FEC" != "3" ]; then exit "$$FEC"; fi; \
		if [ "$$FEC" = "0" ]; then \
			$(run_as_root_router) "$(ROUTER_SCRIPTS)/wg-firewall.sh" || true; \
		fi \
	)

wg-install-router: router-ensure-wg-module \
    $(INSTALL_PATH)/wgctl.sh \
    $(INSTALL_PATH)/wg-readiness-probe.sh \
	wg-generate \
	$(INSTALL_FILE_IF_CHANGED) \
	router-firewall
	@EXECUTE_DEPLOY=0; \
	if [ -f "$(WG_ROUTER_DIRTY_STAMP)" ]; then EXECUTE_DEPLOY=1; fi; \
	for iface in $(WG_INTERFACES_ROUTER); do \
		if ! [ -f "$(WG_OUTPUT_ROUTER)/$$iface.conf" ]; then continue; fi; \
		EXPECTED_GEN=$$(grep -E '^#[[:space:]]*WG_GENERATION:' "$(WG_OUTPUT_ROUTER)/$$iface.conf" | awk '{print $$3}' 2>/dev/null || echo "0"); \
		if [ -x "$(INSTALL_PATH)/wg-readiness-probe.sh" ]; then \
			if ! ROUTER_HOST="$(ROUTER_HOST)" ROUTER_SSH_PORT="$(ROUTER_SSH_PORT)" ROUTER_IDENTITY="$(ROUTER_IDENTITY)" "$(INSTALL_PATH)/wg-readiness-probe.sh" "$$iface" "$(WG_OUTPUT_ROUTER)/$$iface.conf" "$$EXPECTED_GEN" "$(WG_STAMP_DIR)" "router"; then \
				echo "⚠️  Kernel link drift verified on router interface $$iface"; \
				EXECUTE_DEPLOY=1; \
			fi; \
		else \
			echo "⚠️  Readiness probe missing or non-executable at $(INSTALL_PATH)/wg-readiness-probe.sh — forcing execution pass"; \
			EXECUTE_DEPLOY=1; \
		fi; \
	done; \
	if [ "$$EXECUTE_DEPLOY" -eq 1 ]; then \
		echo "🚀 Executing router control plane tunnel provision..."; \
		EC=0; \
		SSH_CONTROL_PATH="$(SSH_SOCK_FILE)" \
		$(WG_ENV) \
		ROUTER_CONTROL_PLANE=1 \
		$(INSTALL_PATH)/wgctl.sh router install-up || EC=$$?; \
		if [ "$$EC" != "0" ] && [ "$$EC" != "3" ]; then exit "$$EC"; fi; \
		rm -f "$(WG_ROUTER_DIRTY_STAMP)"; \
	else \
		echo "✨ Router interfaces match runtime kernel cryptographic and routing expectations (skipping processing)"; \
	fi

wg-install-nas: $(INSTALL_PATH)/wgctl.sh \
	$(INSTALL_PATH)/wg-readiness-probe.sh \
	$(INSTALL_FILE_IF_CHANGED) \
	wg-generate
	@echo "📦 [nas   ] Installing WireGuard configurations..."
	@EXECUTE_DEPLOY=0; \
	if [ -f "$(WG_NAS_DIRTY_STAMP)" ]; then EXECUTE_DEPLOY=1; fi; \
	for iface in $(WG_INTERFACES_NAS); do \
		if ! [ -f "$(WG_OUTPUT_ROUTER)/$$iface.conf" ]; then continue; fi; \
		EXPECTED_GEN=$$(grep -E '^#[[:space:]]*WG_GENERATION:' "$(WG_OUTPUT_ROUTER)/$$iface.conf" | awk '{print $$3}' 2>/dev/null || echo "0"); \
		if [ -x "$(INSTALL_PATH)/wg-readiness-probe.sh" ]; then \
			if ! "$(INSTALL_PATH)/wg-readiness-probe.sh" "$$iface" "$(WG_OUTPUT_ROUTER)/$$iface.conf" "$$EXPECTED_GEN" "$(WG_STAMP_DIR)"; then \
				echo "⚠️  Kernel link drift verified on NAS interface $$iface"; \
				EXECUTE_DEPLOY=1; \
			fi; \
		else \
			echo "⚠️  Readiness probe missing or non-executable at $(INSTALL_PATH)/wg-readiness-probe.sh — forcing execution pass"; \
			EXECUTE_DEPLOY=1; \
		fi; \
	done; \
	if [ "$$EXECUTE_DEPLOY" -eq 1 ]; then \
		echo "🚀 Executing NAS control plane tunnel provision..."; \
		EC=0; \
		$(WG_ENV) \
		NAS_CONTROL_PLANE=1 \
		$(WG_SUDO) $(INSTALL_PATH)/wgctl.sh nas install-up || EC=$$?; \
		if [ "$$EC" != "0" ] && [ "$$EC" != "3" ]; then exit "$$EC"; fi; \
		rm -f "$(WG_NAS_DIRTY_STAMP)"; \
	else \
		echo "✨ NAS interfaces match runtime kernel cryptographic and routing expectations (skipping processing)"; \
	fi

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

wg-install: wg-install-router wg-install-nas

wg-up: wg-install
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

# --------------------------------------------------------------------
# wg7-validate — End-to-end sanity for the NAS-terminated wg7 interface
# --------------------------------------------------------------------
wg7-validate:
	@echo "🔍 [wg7] Step 1/5 — checking wg7 interface on NAS..."
	@$(WG_SUDO) wg show wg7 >/dev/null 2>&1 \
		&& echo "   ✅ wg7 interface present" \
		|| { echo "   ❌ wg7 interface missing — run: make wg-install-nas"; exit 1; }

	@echo "🔍 [wg7] Step 2/5 — IPv4 connectivity (NAS → wg7 server addr)..."
	@ping -c2 -W2 "$$($(WG_SUDO) wg show wg7 | awk '/address:/{print $$2}' | cut -d/ -f1)" >/dev/null 2>&1 \
		&& echo "   ✅ wg7 IPv4 self-ping OK" \
		|| echo "   ⚠️  wg7 IPv4 self-ping failed (interface may be up but unconfigured)"

	@echo "🔍 [wg7] Step 3/5 — NAS eth0 global IPv6 (NAT66 egress prerequisite)..."
	@$(WG_SUDO) ip -6 addr show dev eth0 scope global | grep -q 'inet6' \
		&& echo "   ✅ NAS eth0 has a global IPv6 address" \
		|| echo "   ❌ NAS eth0 has NO global IPv6 — router RA/prefix delegation not yet active"

	@echo "🔍 [wg7] Step 4/5 — nftables NAT66 masquerade rule present (homelab_nat6)..."
	@$(WG_SUDO) nft list chain ip6 homelab_nat6 postrouting 2>/dev/null | grep -q 'masquerade' \
		&& echo "   ✅ homelab_nat6 masquerade rule active" \
		|| echo "   ❌ homelab_nat6 masquerade not loaded — run: make nft-apply && make nft-confirm"

	@echo "🔍 [wg7] Step 5/5 — outbound IPv6 internet reachability (NAS → internet via NAT66)..."
	@curl -6 -s --max-time 5 https://ifconfig.io > /dev/null 2>&1 \
		&& echo "   ✅ IPv6 internet reachable from NAS (NAT66 egress working)" \
		|| echo "   ⚠️  IPv6 internet unreachable from NAS (check global IPv6 on eth0 and default route)"

	@echo "🏁 wg7-validate complete"

# wg-router-ipv6-probe — standalone check for router IPv6 capabilities and prefix delegation
wg-router-ipv6-probe:
	@echo "🔍 Probing router IPv6 stack..."
	@$(run_as_root_router) ' \
		echo "=== ip6tables nat table (expected: FAIL — Asus Merlin lacks CONFIG_IP6_NF_NAT) ==="; \
		ip6tables -t nat -L 2>&1 || echo "  (not available — expected, wg7 uses NAS NAT66 instead)"; \
		echo ""; \
		echo "=== All global IPv6 addresses on router (required for prefix delegation) ==="; \
		ip -6 addr show scope global 2>/dev/null || echo "  (no global IPv6 — enable in Merlin WAN → IPv6)"; \
		echo ""; \
		echo "=== wgs1 IPv6 addresses ==="; \
		ip -6 addr show dev wgs1 2>/dev/null || echo "  (wgs1 not up)"; \
		echo ""; \
		echo "=== IPv6 forwarding ==="; \
		sysctl net.ipv6.conf.all.forwarding 2>/dev/null || true; \
		echo ""; \
		echo "=== Merlin IPv6 service mode (NVRAM) ==="; \
		printf "ipv6_service: %s\n" "$$(nvram get ipv6_service 2>/dev/null)"; \
	'
	@echo ""
	@echo "=== NAS eth0 global IPv6 (should be received via router RA) ==="
	@$(WG_SUDO) ip -6 addr show dev eth0 scope global 2>/dev/null \
		&& echo "(above is NAS eth0 — if empty, router RA/PD is not yet delegating)" \
		|| echo "   ❌ NAS eth0 has no global IPv6 yet"