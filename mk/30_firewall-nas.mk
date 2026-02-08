# --------------------------------------------------------------------
# mk/30_firewall-nas.mk — NAS firewall invariants
# --------------------------------------------------------------------
# CONTRACT:
# - Explicitly allow trusted subnets to access NAS services
# - Default-deny posture preserved
# - Idempotent and safe to re-run
# --------------------------------------------------------------------

NAS_IP              := 10.89.12.4
ROUTER_WG_SUBNET    := 10.89.13.0/24

.PHONY: firewall-nas

firewall-nas: ensure-run-as-root
	@echo "🔥 Allowing router-terminated WireGuard clients to access NAS"

	# Allow all TCP services from router-terminated WG
	@if ! iptables -C INPUT -s $(ROUTER_WG_SUBNET) -d $(NAS_IP) -p tcp -j ACCEPT 2>/dev/null; then \
		iptables -I INPUT -s $(ROUTER_WG_SUBNET) -d $(NAS_IP) -p tcp -j ACCEPT; \
	fi

	# Allow all UDP services from router-terminated WG
	@if ! iptables -C INPUT -s $(ROUTER_WG_SUBNET) -d $(NAS_IP) -p udp -j ACCEPT 2>/dev/null; then \
		iptables -I INPUT -s $(ROUTER_WG_SUBNET) -d $(NAS_IP) -p udp -j ACCEPT; \
	fi
