# --------------------------------------------------------------------
# mk/wireguard/10_env.mk — WireGuard Environment & Constants
# --------------------------------------------------------------------

WG_OUTPUT_ROUTER := $(WG_ROOT)/output/router
WG_FIREWALL      := $(WG_OUTPUT_ROUTER)/wg-firewall.sh

# Persistent state tracking markers
WG_ROUTER_DIRTY_STAMP := $(STAMP_DIR_ROOT)/wg_router_dirty.stamp
WG_NAS_DIRTY_STAMP    := $(STAMP_DIR_ROOT)/wg_nas_dirty.stamp

# Explicit interface inventory managed by the control plane
WG_INTERFACES_ROUTER := wgs1

# Canonical environment block for router/NAS control-plane operations
WG_ENV = \
		ROUTER_HOST="$(ROUTER_HOST)" \
		ROUTER_SSH_PORT="$(ROUTER_SSH_PORT)" \
		ROUTER_WG_DIR="$(ROUTER_WG_DIR)" \
		WG_ROOT="$(WG_ROOT)"

# Unified sudo wrapper for homelab root operations
WG_SUDO := sudo --preserve-env=ROUTER_HOST,ROUTER_ADDR,ROUTER_SSH_PORT,ROUTER_WG_DIR,WG_ROOT,WG_SUBNETS_MK,SSH_AUTH_SOCK,ROUTER_IDENTITY,SSH_CONTROL_PATH

WG_SUBNETS_MK := $(STAMP_DIR_ROOT)/wg-subnets.mk
WG_INTERFACE_LIST_STAMP := $(STAMP_DIR_ROOT)/wg-interfaces.mk
