# mk/host/10_route.mk
# ------------------------------------------------------------
# ROUTING LAYER (HOST + REMOTE)
# ------------------------------------------------------------

# Generic remote default route healer
define REMOTE_DEFAULT_ROUTE_HEALER
	if [ "$(1)" = "$(SSH_HOST_ROUTER)" ]; then \
		echo "❌ REMOTE_DEFAULT_ROUTE_HEALER must NEVER be used on the router (WAN routing is ISP/firmware controlled)"; \
		exit 1; \
	fi; \
	ssh $(1) ' \
		if ! ip route show default | grep -q "$(LAN_ROUTER)"; then \
			echo "⚠️ Default route missing on $(1) — restoring"; \
			sudo ip route add default via "$(LAN_ROUTER)" dev $(2) || true; \
			echo "✅ Default route restored on $(1)"; \
		else \
			echo "🟢 Default route OK on $(1)"; \
		fi'
endef


# ------------------------------------------------------------
# HOST DEFAULT ROUTE HEALER (always safe, always local)
# ------------------------------------------------------------
.PHONY: ensure-host-default-route
ensure-host-default-route: secrets-ready
	@$(call WITH_SECRETS, sh -c '\
		IFACE=$$(ip route get "$$ROUTER_ADDR" | awk "/dev/ {print \$$5}"); \
		if [ -z "$$IFACE" ]; then \
			echo "❌ Cannot determine host LAN interface for reaching $$ROUTER_ADDR"; \
			exit 1; \
		fi; \
		if ! ip route show default | grep -q "$$ROUTER_ADDR"; then \
			echo "⚠️ Default gateway missing! Restoring path to $$ROUTER_ADDR via $$IFACE..."; \
			$(run_as_root) ip route add default via "$$ROUTER_ADDR" dev "$$IFACE" 2>/dev/null || true; \
			echo "✅ Default gateway restored"; \
		else \
			echo "🟢 Default gateway OK"; \
		fi \
	')

# ------------------------------------------------------------
# HOST SPECIFIC ROUTE HEALER
# ------------------------------------------------------------
.PHONY: ensure-hub01-default-route
ensure-hub01-default-route: install-ssh-config secrets-ready
	@$(call REMOTE_DEFAULT_ROUTE_HEALER,$(SSH_HOST_HUB01),$(HUB01_LAN_IFACE))

# ------------------------------------------------------------
# BOOTSTRAP TARGETS (non-recursive, availability-aware)
# ------------------------------------------------------------

# NAS
nas-bootstrap: ensure-host-default-route
nas-bootstrap:
	@if ! ping -c1 $(NAS_ADDR) >/dev/null 2>&1; then \
		echo "⚠️ NAS unreachable — skipping nas-bootstrap"; \
		exit 0; \
	fi; \
	echo "🔧 NAS reachable — healing route…"; \
	$(call REMOTE_DEFAULT_ROUTE_HEALER,$(SSH_HOST_NAS),$(NAS_LAN_IFACE)); \
	echo "🔧 Running NAS bootstrap…"; \
	# TODO: NAS bootstrap commands here


# Synology
synology-bootstrap: ensure-host-default-route
synology-bootstrap:
	@if ! ping -c1 $(SYNOLOGY_ADDR) >/dev/null 2>&1; then \
		echo "⚠️ Synology unreachable — skipping synology-bootstrap"; \
		exit 0; \
	fi; \
	echo "🔧 Synology reachable — healing route…"; \
	$(call REMOTE_DEFAULT_ROUTE_HEALER,$(SSH_HOST_SYNOLOGY),$(SYNO_LAN_IFACE)); \
	echo "🔧 Running Synology bootstrap…"; \
	# TODO: Synology bootstrap commands here


# QNAP
qnap-bootstrap: ensure-host-default-route
qnap-bootstrap:
	@if ! ping -c1 $(QNAP_ADDR) >/dev/null 2>&1; then \
		echo "⚠️ QNAP unreachable — skipping qnap-bootstrap"; \
		exit 0; \
	fi; \
	echo "🔧 QNAP reachable — healing route…"; \
	$(call REMOTE_DEFAULT_ROUTE_HEALER,$(SSH_HOST_QNAP),$(QNAP_LAN_IFACE)); \
	echo "🔧 Running QNAP bootstrap…"; \
	# TODO: QNAP bootstrap commands here


# hub01
hub01-bootstrap: ensure-host-default-route ensure-hub01-default-route
hub01-bootstrap:
	@if ! ssh -o ConnectTimeout=3 $(SSH_HOST_HUB01) 'true' >/dev/null 2>&1; then \
		echo "⚠️ hub01 unreachable — skipping hub01-bootstrap"; \
		exit 0; \
	fi; \
	echo "🔧 hub01 reachable — healing route…"; \
	$(call REMOTE_DEFAULT_ROUTE_HEALER,$(SSH_HOST_HUB01),$(HUB01_LAN_IFACE)); \
	echo "🔧 Running hub01 bootstrap…"; \
	# TODO: hub01 bootstrap commands here
