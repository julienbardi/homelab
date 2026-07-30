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
	ssh "$(1)" ' \
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
# ------------------------------------------------------------
# ensure-host-default-route
# ------------------------------------------------------------
STAMP_DIR_ROOT       := /var/lib/homelab
STAMP_HOST_ROUTE_TS  := $(STAMP_DIR_ROOT)/host-default-route.last-check
STAMP_TTL_SECONDS    := 30

.PHONY: ensure-host-default-route
ensure-host-default-route: | $(STAMP_DIR_ROOT) $(run_as_root)
	@{ \
		NOW=$$(date +%s); \
		LAST=0; \
		if [ -f "$(STAMP_HOST_ROUTE_TS)" ]; then \
			LAST=$$(cat "$(STAMP_HOST_ROUTE_TS)" 2>/dev/null || echo 0); \
		fi; \
		AGE=$$(expr $$NOW - $$LAST); \
		if [ $$AGE -lt $(STAMP_TTL_SECONDS) ]; then \
			echo "⏩ ensure-host-default-route (fast-path, age $$AGE s < $(STAMP_TTL_SECONDS)s)"; \
			exit 0; \
		fi; \
		\
		IFACE=$$(ip route get "$$ROUTER_ADDR" | \
			awk '{for(i=1;i<=NF;i++) if($$i=="dev") print $$(i+1)}' | head -n1); \
		if [ -z "$$IFACE" ]; then \
			echo "❌ Cannot determine host LAN interface for reaching $$ROUTER_ADDR"; \
			exit 1; \
		fi; \
		if ! ip route show default | grep -q "$$ROUTER_ADDR"; then \
			$(run_as_root) ip route add default via "$$ROUTER_ADDR" dev "$$IFACE" || true; \
			echo "✅ Default route via $$ROUTER_ADDR on $$IFACE added"; \
		else \
			echo "🟢 Default route already via $$ROUTER_ADDR on $$IFACE"; \
		fi; \
		echo $$NOW | $(run_as_root) tee "$(STAMP_HOST_ROUTE_TS)" >/dev/null; \
	}




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
nas-bootstrap: install-ssh-config ensure-host-default-route
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
synology-bootstrap: install-ssh-config ensure-host-default-route
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
qnap-bootstrap: install-ssh-config ensure-host-default-route
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
hub01-bootstrap: install-ssh-config ensure-hub01-default-route
hub01-bootstrap:
	@if ! ssh -o ConnectTimeout=3 $(SSH_HOST_HUB01) 'true' >/dev/null 2>&1; then \
		echo "⚠️ hub01 unreachable — skipping hub01-bootstrap"; \
		exit 0; \
	fi; \
	echo "🔧 hub01 reachable — healing route…"; \
	$(call REMOTE_DEFAULT_ROUTE_HEALER,$(SSH_HOST_HUB01),$(HUB01_LAN_IFACE)); \
	echo "🔧 Running hub01 bootstrap…"; \
	# TODO: hub01 bootstrap commands here
