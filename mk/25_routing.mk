# ============================================================
# mk/25_routing.mk — IPv4 routing convergence
# ============================================================
# ----------------------------------------------------------------------------
# IPv6 Routing Policy (ULA-only LAN)
#
# The NAS MUST NOT have an IPv6 default route.
#
# Reason:
#   - The LAN uses a ULA-only IPv6 prefix (fd89:7a3b:42c0::/64)
#   - The router does NOT advertise a global IPv6 prefix
#   - The router has NO IPv6 upstream connectivity
#   - A default IPv6 route would blackhole traffic and break DNS/Headscale/WG
#
# Therefore:
#   - Only on-link IPv6 routes must exist
#   - Any IPv6 default route is a configuration error and must be removed
# ----------------------------------------------------------------------------

.PHONY: ensure-default-route

ensure-default-route:
	@set -euo pipefail; \
	echo "🔍 Ensuring IPv4 default route via $(LAN_ROUTER)"; \
	current_gw=$$(ip route show default | awk '/default/ {print $$3}'); \
	current_dev=$$(ip route show default | awk '/default/ {print $$5}'); \
	\
	if [ -z "$$current_gw" ]; then \
		echo "⚠️  No default route present. Applying converge route..."; \
		$(run_as_root) ip route add default via "$(LAN_ROUTER)" dev eth0; \
		exit 0; \
	fi; \
	\
	if [ "$$current_gw" != "$(LAN_ROUTER)" ]; then \
		echo "⚠️  Default route drift detected: $$current_gw (dev $$current_dev)"; \
		if [ "$(FORCE)" != "1" ]; then \
			echo "👉 Re-run with: FORCE=1 make homelab-all"; \
			exit 1; \
		fi; \
		echo "🔧 Forcing default route to $(LAN_ROUTER)"; \
		$(run_as_root) ip route replace default via "$(LAN_ROUTER)" dev eth0; \
		exit 0; \
	fi; \
	\
	# IPv6 sanity check — NAS must NOT have a default IPv6 route \
	if ip -6 route show default >/dev/null 2>&1; then \
		echo "❌ IPv6 default route detected — invalid on ULA-only LAN"; \
		echo "   The NAS must NOT have an IPv6 default gateway."; \
		echo "   Remove it manually or fix router RA configuration."; \
		exit 1; \
	fi; \
	\
	echo "♻️ IPv4 default route already converged: $$current_gw (dev $$current_dev)"
