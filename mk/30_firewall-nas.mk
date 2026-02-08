# --------------------------------------------------------------------
# mk/30_firewall-nas.mk — NAS firewall invariants
# --------------------------------------------------------------------
# CONTRACT:
# - Explicitly allow trusted subnets to access NAS services
# - Default-deny posture preserved
# - Idempotent and safe to re-run
# --------------------------------------------------------------------

ROUTER_WG_SUBNET := 10.89.13.0/24
IPTABLES         := /usr/sbin/iptables

$(if $(wildcard $(IPTABLES)),,$(error iptables not found at $(IPTABLES)))

.PHONY: firewall-nas

firewall-nas: ensure-run-as-root
	@echo "🔥 Allowing router-terminated WireGuard clients to access NAS"

	# Allow all TCP services from router-terminated WG
<<<<<<< HEAD
	@if ! $(run_as_root) $(IPTABLES) -C INPUT -s $(ROUTER_WG_SUBNET) -d $(NAS_LAN_IP) -p tcp -j ACCEPT 2>/dev/null; then \
		$(run_as_root) $(IPTABLES) -I INPUT -s $(ROUTER_WG_SUBNET) -d $(NAS_LAN_IP) -p tcp -j ACCEPT; \
	fi

	# Allow all UDP services from router-terminated WG
	@if ! $(run_as_root) $(IPTABLES) -C INPUT -s $(ROUTER_WG_SUBNET) -d $(NAS_LAN_IP) -p udp -j ACCEPT 2>/dev/null; then \
		$(run_as_root) $(IPTABLES) -I INPUT -s $(ROUTER_WG_SUBNET) -d $(NAS_LAN_IP) -p udp -j ACCEPT; \
=======
	@if ! @$(run_as_root) $(IPTABLES) -C INPUT -s $(ROUTER_WG_SUBNET) -d $(NAS_LAN_IP) -p tcp -j ACCEPT 2>/dev/null; then \
		@$(run_as_root) $(IPTABLES) -I INPUT -s $(ROUTER_WG_SUBNET) -d $(NAS_LAN_IP) -p tcp -j ACCEPT; \
	fi

	# Allow all UDP services from router-terminated WG
	@if ! @$(run_as_root) $(IPTABLES) -C INPUT -s $(ROUTER_WG_SUBNET) -d $(NAS_LAN_IP) -p udp -j ACCEPT 2>/dev/null; then \
		@$(run_as_root) $(IPTABLES) -I INPUT -s $(ROUTER_WG_SUBNET) -d $(NAS_LAN_IP) -p udp -j ACCEPT; \
>>>>>>> bf25ced173bc010a7ee411f67a954f25c80e4715
	fi
