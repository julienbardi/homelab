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

net-tunnel-preflight:
	@NETDEV="$$(ip -o route get 8.8.8.8 | awk '{print $$5}')" && \
		$(run_as_root) ethtool -k "$$NETDEV" | grep -q 'rx-udp-gro-forwarding: on' || \
		$(run_as_root) ethtool -K "$$NETDEV" rx-udp-gro-forwarding on rx-gro-list off
	$(eval NET_TUNNEL_PREFLIGHT_DONE := yes)
