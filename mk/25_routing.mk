# ============================================================
# mk/25_routing.mk — IPv4 + IPv6 routing convergence
# ============================================================
#
# IPv6 Routing Policy (NAS)
# ----------------------------------------
# The NAS participates in IPv6 on the LAN using:
#   - ULA prefix:    fd89:7a3b:42c0::/64  (stable, always present)
#   - Global prefix: 2xxx::/64            (from router RA / ISP delegation)
#   - Link-local:    fe80::/64
#   - Token-based addressing (::4) on both prefixes
#
# The router MUST provide:
#   - IPv6 default route (via RA or static)
#   - ISP-delegated global prefix (for NAT66 on wg7)
#
# Therefore:
#   - The NAS MUST have a ULA IPv6 address (enforced).
#   - The NAS MUST have a global IPv6 address from the router RA.
#   - The NAS MUST have an IPv6 default route via the router.
#
# Rationale:
#   - NAT66 masquerade on the NAS requires a global source address on eth0.
#   - Without it, wg7 IPv6 internet silently black-holes (ULA not routable by ISPs).
#   - The delegated global prefix is used ONLY for egress NAT66; it is NOT
#     advertised to WG clients or LAN hosts (no delegated IPv6 in tunnel configs).
#
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
	# IPv6 routing invariants (RA-enabled) \
	# ------------------------------------------------------------ \
	\
	# 1. Require IPv6 default route (router must advertise one for NAT66 to work) \
	if ! ip -6 route show default | grep -q .; then \
		echo "⚠️ No IPv6 default route - router RA not yet configured for IPv6."; \
		echo "   wg7 IPv6 internet will not work until the router delegates a prefix."; \
		echo "   This is non-fatal: IPv6 clients will fast-fail via ICMPv6 and use IPv4."; \
	else \
		echo "✅ IPv6 default route present"; \
	fi; \
	\
	# 2. Require global IPv6 address (2xxx::/3) — needed for NAT66 masquerade source \
	if ! ip -6 addr show dev eth0 | grep -q 'inet6 2'; then \
		echo "⚠️ No global IPv6 address on eth0 — router not yet delegating a prefix."; \
		echo "   NAT66 will fallback to IPv4-only egress."; \
		echo "   This is non-fatal: see docs/network-contract.md IPv6 Internet section."; \
	else \
		echo "✅ Global IPv6 address present on eth0 (NAT66 masquerade source ready)"; \
	fi; \
	\
	# 3+4. Require ULA IPv6 on eth0 AND router ULA advertisement \
	if ! ip -6 addr show dev eth0 | grep -q 'inet6 fd'; then \
		echo "❌ No ULA IPv6 address detected on eth0 — required invariant"; \
		echo "❌ Router is NOT advertising a ULA prefix — LAN IPv6 broken"; \
		exit 1; \
	fi; \
	\
	# 5. WG clients must NOT receive delegated global IPv6 (enforced in wg-generate-configs.sh) \
	echo "✅ IPv6 routing invariants checked (ULA + global + default route)";
