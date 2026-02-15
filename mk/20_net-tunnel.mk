# --------------------------------------------------------------------
# mk/20_net-tunnel.mk — UDP tunnel network invariants
# --------------------------------------------------------------------
# CONTRACT:
# - Ensures NIC offload settings compatible with UDP tunnels
# - Applies to WireGuard, Tailscale, and future UDP-based tunnels
# - Idempotent and safe to re-run
# --------------------------------------------------------------------

# Set when UDP tunnel preflight has been executed in this make invocation
NET_TUNNEL_PREFLIGHT_DONE :=

ifdef CI
define warn_if_no_net_tunnel_preflight
$(if $(NET_TUNNEL_PREFLIGHT_DONE),,\
	$(error UDP tunnel preflight missing))
endef
endif

.PHONY: net-tunnel-preflight

net-tunnel-preflight: ensure-run-as-root net-tunnel-routing
	@NETDEV="$$(ip -o route get 8.8.8.8 | awk '{print $$5}')" && \
		$(run_as_root) ethtool -k "$$NETDEV" | grep -q 'rx-udp-gro-forwarding: on' || \
		$(run_as_root) ethtool -K "$$NETDEV" rx-udp-gro-forwarding on rx-gro-list off
	$(eval NET_TUNNEL_PREFLIGHT_DONE := yes)

# Router-terminated WireGuard return path
# Required for symmetric routing when WG terminates on the router
ROUTER_WG_SUBNET := 10.89.13.0/24
ROUTER_LAN_GW    := $(ROUTER_LAN_IP)

.PHONY: net-tunnel-routing

net-tunnel-routing: ensure-run-as-root
	@echo "🛣️  Ensuring return route for router-terminated WireGuard"
	@$(run_as_root) ip route replace $(ROUTER_WG_SUBNET) via $(ROUTER_LAN_GW)

