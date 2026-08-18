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
STAMP_HOST_ROUTE_TS  := $(STAMP_DIR_ROOT)/host-default-route.last-check
STAMP_TTL_SECONDS    := 30

.PHONY: ensure-host-default-route
ensure-host-default-route: ensure-state-dirs
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
		IFACE=$$(ip route get "$(LAN_ROUTER)" | \
			awk '{for(i=1;i<=NF;i++) if($$i=="dev") print $$(i+1)}' | head -n1); \
		if [ -z "$$IFACE" ]; then \
			echo "❌ Cannot determine host LAN interface for reaching $(LAN_ROUTER)"; \
			exit 1; \
		fi; \
		if ! ip route show default | grep -q "$(LAN_ROUTER)"; then \
			$(run_as_root) ip route add default via "$(LAN_ROUTER)" dev "$$IFACE" || true; \
			echo "✅ Default route via $(LAN_ROUTER) on $$IFACE added"; \
		else \
			echo "🟢 Default route already via $(LAN_ROUTER) on $$IFACE"; \
		fi; \
		$(run_as_root) mkdir -p "$$(dirname "$(STAMP_HOST_ROUTE_TS)")"; \
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
	@if ping -c1 $(LAN_NAS) >/dev/null 2>&1; then \
		echo "🟢 NAS $(LAN_NAS) reachable"; \
	else \
		echo "⚠️ NAS $(LAN_NAS) unreachable"; \
		exit 0; \
	fi

# Synology
synology-bootstrap: install-ssh-config ensure-host-default-route
	@if ping -c1 $(LAN_SYNOLOGY) >/dev/null 2>&1; then \
		echo "🟢 NAS $(LAN_SYNOLOGY) reachable"; \
	else \
		echo "⚠️ NAS $(LAN_SYNOLOGY) unreachable"; \
		exit 0; \
	fi

# QNAP
.PHONY: qnap-bootstrap
qnap-bootstrap: install-ssh-config ensure-host-default-route
	@if ! ping -c1 $(QNAP_ADDR) >/dev/null 2>&1; then \
		echo "⚠️ QNAP unreachable — skipping qnap-bootstrap"; \
		exit 0; \
	fi; \
	echo "🔧 QNAP reachable — healing route…"; \
	$(call REMOTE_DEFAULT_ROUTE_HEALER,$(SSH_HOST_QNAP),$(QNAP_LAN_IFACE)); \
	echo "🔧 Running QNAP bootstrap…"; \
	# TODO: QNAP bootstrap commands here

# hub01
.PHONY: hub01-bootstrap
hub01-bootstrap: install-ssh-config ensure-hub01-default-route
	@if ! ssh -o ConnectTimeout=3 $(SSH_HOST_HUB01) 'true' >/dev/null 2>&1; then \
		echo "⚠️ hub01 unreachable — skipping hub01-bootstrap"; \
		exit 0; \
	fi; \
	echo "🔧 hub01 reachable — healing route…"; \
	$(call REMOTE_DEFAULT_ROUTE_HEALER,$(SSH_HOST_HUB01),$(HUB01_LAN_IFACE)); \
	echo "🔧 Running hub01 bootstrap…"; \
	# TODO: hub01 bootstrap commands here