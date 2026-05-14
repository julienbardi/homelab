# ============================================================
# mk/25_routing.mk — IPv4 routing convergence
# ============================================================
#
# IPv6 Routing Policy (LAN-only, ULA-only)
# ----------------------------------------
# The NAS participates in IPv6 *only inside the LAN* using:
#   - ULA prefix: fd89:7a3b:42c0::/64
#   - Link-local: fe80::/64
#   - Token-based addressing (::4)
#
# The router does NOT provide:
#   - Global IPv6 prefix (2xxx::/3)
#   - IPv6 upstream connectivity
#   - IPv6 default route
#
# Therefore:
#   - The NAS MUST NOT have an IPv6 default route.
#   - The NAS MUST NOT have any global IPv6 address.
#   - The NAS MUST have a ULA IPv6 address.
#
# Rationale:
#   - A global IPv6 prefix would break deterministic routing.
#   - An IPv6 default route would blackhole traffic (router has no upstream).
#   - ULA-only IPv6 keeps LAN IPv6 fast, deterministic, and stable.
#
# This target enforces the above invariants.
# ============================================================

.PHONY: ensure-default-route

ensure-default-route:
	@set -euo pipefail; \
	echo "🔍 Ensuring IPv4 default route via $(LAN_ROUTER)"; \
	current_gw=$$(ip route show default | awk '/default/ {print $$3}'); \
	current_dev=$$(ip route show default | awk '/default/ {print $$5}'); \
	\
	# ------------------------------------------------------------ \
	# IPv4 default route convergence \
	# ------------------------------------------------------------ \
	if [ -z "$$current_gw" ]; then \
		echo "⚠️  No IPv4 default route present. Applying converge route..."; \
		$(run_as_root) ip route add default via "$(LAN_ROUTER)" dev eth0; \
		exit 0; \
	fi; \
	\
	if [ "$$current_gw" != "$(LAN_ROUTER)" ]; then \
		echo "⚠️  IPv4 default route drift detected: $$current_gw (dev $$current_dev)"; \
		if [ "$(FORCE)" != "1" ]; then \
			echo "👉 Re-run with: FORCE=1 make homelab-all"; \
			exit 1; \
		fi; \
		echo "🔧 Forcing IPv4 default route to $(LAN_ROUTER)"; \
		$(run_as_root) ip route replace default via "$(LAN_ROUTER)" dev eth0; \
		exit 0; \
	fi; \
	\
	# ------------------------------------------------------------ \
	# IPv6 LAN-only invariants \
	# ------------------------------------------------------------ \
	\
	# 1. Reject any IPv6 default route (router must NOT advertise one) \
	if ip -6 route show default | grep -q .; then \
		echo "❌ IPv6 default route detected — forbidden in IPv6 LAN-only mode"; \
		echo "   Fix router RA configuration or remove the route manually."; \
		exit 1; \
	fi; \
	\
	# 2. Reject global IPv6 addresses (2xxx::/3) \
	if ip -6 addr show dev eth0 | grep -q 'inet6 2'; then \
		echo "❌ Global IPv6 prefix detected (2xxx::/3) — forbidden in LAN-only mode"; \
		echo "   Router must NOT advertise a global IPv6 prefix."; \
		exit 1; \
	fi; \
	\
	# 3. Require ULA IPv6 address (fd00::/8) \
	if ! ip -6 addr show dev eth0 | grep -q 'inet6 fd'; then \
		echo "❌ No ULA IPv6 address detected on eth0 — required for LAN-only IPv6"; \
		exit 1; \
	fi; \
	\
	# ------------------------------------------------------------ \
	# Router RA verification (LAN-only IPv6) \
	# ------------------------------------------------------------ \
	# The router must advertise:
	#   - ULA prefix only (fd00::/8)
	#   - NO global prefix (2xxx::/3)
	#   - NO IPv6 default route
	#   - NO DHCPv6
	#
	# We verify this indirectly by inspecting what the NAS receives.
	# ------------------------------------------------------------ \
	\
	# 4. Router must advertise a ULA prefix \
	if ! ip -6 addr show dev eth0 | grep -q 'inet6 fd'; then \
		echo "❌ Router is NOT advertising a ULA prefix — LAN-only IPv6 broken"; \
		exit 1; \
	fi; \
	\
	# 5. Router must NOT advertise a global prefix \
	if ip -6 addr show dev eth0 | grep -q 'inet6 2'; then \
		echo "❌ Router is leaking a global IPv6 prefix (2xxx::/3) — forbidden"; \
		exit 1; \
	fi; \
	\
	# 6. Router must NOT advertise an IPv6 default route \
	if ip -6 route show default | grep -q .; then \
		echo "❌ Router is advertising an IPv6 default route — forbidden"; \
		exit 1; \
	fi; \
	\
	echo "♻️ IPv4 default route converged: $$current_gw (dev $$current_dev)"; \
	echo "✨ IPv6 LAN-only invariants satisfied (ULA present, no global prefix, no default route)"
