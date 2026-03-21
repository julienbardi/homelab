# --------------------------------------------------------------------
# mk/30_firewall-nas.mk — NAS firewall invariants
# --------------------------------------------------------------------
# CONTRACT:
# - Explicitly allow trusted subnets to access NAS services
# - Default-deny posture preserved
# - Idempotent and safe to re-run
# --------------------------------------------------------------------

# Derived from authoritative wg-interfaces.tsv via wg-plan-subnets.sh
ROUTER_WG_SUBNET   := $(WG_ROUTER_SUBNET_V4)
ROUTER_WG_SUBNET6  := $(WG_ROUTER_SUBNET_V6)

IPTABLES  := /usr/sbin/iptables
IP6TABLES := /usr/sbin/ip6tables

$(if $(wildcard $(IPTABLES)),,$(error iptables not found at $(IPTABLES)))
$(if $(wildcard $(IP6TABLES)),,$(error ip6tables not found at $(IP6TABLES)))

.PHONY: firewall-nas

firewall-nas: ensure-run-as-root
	@echo "🔥 Allowing router-terminated WireGuard clients to access NAS"

	@if ! $(run_as_root) $(IPTABLES) -C INPUT -s $(ROUTER_WG_SUBNET)   -d $(NAS_LAN_IP) -p tcp -j ACCEPT 2>/dev/null; then \
	      $(run_as_root) $(IPTABLES) -I INPUT -s $(ROUTER_WG_SUBNET)   -d $(NAS_LAN_IP) -p tcp -j ACCEPT; \
	fi

	@if ! $(run_as_root) $(IPTABLES) -C INPUT -s $(ROUTER_WG_SUBNET)   -d $(NAS_LAN_IP) -p udp -j ACCEPT 2>/dev/null; then \
	      $(run_as_root) $(IPTABLES) -I INPUT -s $(ROUTER_WG_SUBNET)   -d $(NAS_LAN_IP) -p udp -j ACCEPT; \
	fi

	@if ! $(run_as_root) $(IP6TABLES) -C INPUT -s $(ROUTER_WG_SUBNET6) -d $(NAS_LAN_IP6) -p tcp -j ACCEPT 2>/dev/null; then \
	      $(run_as_root) $(IP6TABLES) -I INPUT -s $(ROUTER_WG_SUBNET6) -d $(NAS_LAN_IP6) -p tcp -j ACCEPT; \
	fi

	@if ! $(run_as_root) $(IP6TABLES) -C INPUT -s $(ROUTER_WG_SUBNET6) -d $(NAS_LAN_IP6) -p udp -j ACCEPT 2>/dev/null; then \
	      $(run_as_root) $(IP6TABLES) -I INPUT -s $(ROUTER_WG_SUBNET6) -d $(NAS_LAN_IP6) -p udp -j ACCEPT; \
	fi
