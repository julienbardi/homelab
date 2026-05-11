# ============================================================
# mk/25_routing.mk — IPv4 routing convergence
# ============================================================

.PHONY: ensure-default-route

ensure-default-route:
	@set -euo pipefail; \
	echo "🔍 Ensuring IPv4 default route via $(NAS_LAN_GW4)"; \
	current_gw=$$(ip route show default | awk '/default/ {print $$3}'); \
	current_dev=$$(ip route show default | awk '/default/ {print $$5}'); \
	\
	if [ -z "$$current_gw" ]; then \
		echo "⚠️  No default route present. Applying converge route..."; \
		$(run_as_root) ip route add default via "$(NAS_LAN_GW4)" dev eth0; \
		exit 0; \
	fi; \
	\
	if [ "$$current_gw" != "$(NAS_LAN_GW4)" ]; then \
		echo "⚠️  Default route drift detected: $$current_gw (dev $$current_dev)"; \
		if [ "$(FORCE)" != "1" ]; then \
			echo "👉 Re-run with: FORCE=1 make homelab-all"; \
			exit 1; \
		fi; \
		echo "🔧 Forcing default route to $(NAS_LAN_GW4)"; \
		$(run_as_root) ip route replace default via "$(NAS_LAN_GW4)" dev eth0; \
		exit 0; \
	fi; \
	\
	echo "♻️ IPv4 default route already converged: $$current_gw (dev $$current_dev)"
