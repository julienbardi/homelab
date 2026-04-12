# ============================================================
# mk/20_net-tunnel.mk — UDP tunnel network invariants
# ============================================================

# Use the physical interface from constants (e.g., eth0)
# Ensure this matches your DXP 4800+ hardware
PRIMARY_IFACE ?= eth0

# Derived from authoritative wg-interfaces.tsv via wg-plan-subnets.sh
ROUTER_WG_SUBNET := $(WG_ROUTER_SUBNET_V4)
ROUTER_LAN_GW    := $(ROUTER_LAN_IP)

.PHONY: net-tunnel-persist net-tunnel-routing net-tunnel-status

# 1. Persistent NIC Offload Logic ---
UDEV_OFFLOAD_SRC := $(REPO_ROOT)config/udev/99-udp-offloads.rules
UDEV_OFFLOAD_DST := /etc/udev/rules.d/99-udp-offloads.rules

net-tunnel-persist: ensure-run-as-root
	@echo "🛠️  Deploying persistent UDP offload rules..."
	@$(call install_file,$(UDEV_OFFLOAD_SRC),$(UDEV_OFFLOAD_DST),root,root,0644)
	@$(run_as_root) udevadm control --reload-rules && $(run_as_root) udevadm trigger
	@echo "✅ udev rules applied"

# 2. Assert current runtime state (The "No Lie" check)
net-tunnel-preflight: ensure-run-as-root net-tunnel-routing
	@echo "🔍 Verifying UDP GRO offloads on $(PRIMARY_IFACE)"
	@$(run_as_root) ethtool -k $(PRIMARY_IFACE) | grep -q 'rx-udp-gro-forwarding: on' || \
		{ echo "⚠️ Offloads not active. Running fix..."; $(run_as_root) ethtool -K $(PRIMARY_IFACE) rx-udp-gro-forwarding on rx-gro-list off; }

# 3. Routing Invariants
net-tunnel-routing: ensure-run-as-root
	@echo "📍  Ensuring return route for $(ROUTER_WG_SUBNET)"
	@$(run_as_root) ip route replace $(ROUTER_WG_SUBNET) via $(ROUTER_LAN_GW)