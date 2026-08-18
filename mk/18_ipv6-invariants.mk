# mk/18_ipv6-invariants.mk
# --------------------------------------------------------------------
# CONTRACT: \
# - Ensures IPv6 topology matches homelab design. \
# - $(HOST_IPV6_IFACE): MUST have ULA always. \
# - $(HOST_IPV6_IFACE): MUST have GUA + default route only when router delegates a prefix. \
# - All other interfaces MUST NOT have global IPv6. \
# --------------------------------------------------------------------

HOST_IPV6_IFACE := $(shell \
	iface="$$(ip -o -6 addr show scope global 2>/dev/null | awk '!/docker|br-|veth|wg|wt|tailscale|tun|tap|lo|nic/ {print $$2; exit}')"; \
	if [ -n "$$iface" ]; then \
		echo "$$iface"; \
	else \
		ip -o link show 2>/dev/null | awk -F': ' '!/docker|br-|veth|wg|wt|tailscale|tun|tap|lo|nic/ && (/vmbr0|eth0|eno[0-9]|enp[0-9]|br0/) {print $$2; exit}'; \
	fi \
)

.PHONY: verify-ipv6-invariants

verify-ipv6-invariants:
	@set -eu; \
	echo "🔍 Verifying IPv6 invariants..."; \
	\
	# $(HOST_IPV6_IFACE) MUST have a ULA (fdxx::) \
	if ! ip -6 addr show dev "$(HOST_IPV6_IFACE)" 2>/dev/null | grep -Eq 'inet6 fd[0-9a-f]'; then \
		echo "❌ $(HOST_IPV6_IFACE) missing ULA IPv6 address"; exit 1; \
	fi; \
	\
	# Detect if $(HOST_IPV6_IFACE) has a global IPv6 (2xxx::) \
	HAS_GUA=$$(ip -6 addr show dev "$(HOST_IPV6_IFACE)" 2>/dev/null | grep -Eq 'inet6 2[0-9a-f]' && echo yes || echo no); \
	\
	if [ "$$HAS_GUA" = "yes" ]; then \
		# If GUA exists, default route MUST exist \
		if ! ip -6 route show default | grep -q "dev $(HOST_IPV6_IFACE)"; then \
			echo "❌ $(HOST_IPV6_IFACE) has global IPv6 but no default IPv6 route"; exit 1; \
		fi; \
		echo "✅ $(HOST_IPV6_IFACE): GUA + default IPv6 route OK"; \
	else \
		echo "ℹ️ $(HOST_IPV6_IFACE) has no global IPv6 — skipping default route check (router not delegating prefix)"; \
	fi; \
	\
	# All other interfaces MUST NOT have global IPv6 \
	for IFACE in $$(ls /sys/class/net); do \
		# Skip loopback, primary IPv6 interface, and standard virtual/tunnel/bridge interfaces \
		if [ "$$IFACE" = "lo" ] || [ "$$IFACE" = "$(HOST_IPV6_IFACE)" ] || echo "$$IFACE" | grep -Eq '^(wg|veth|fwbr|docker|br|tap|tun|bonding_masters)'; then \
			continue; \
		fi; \
		\
		# Check forbidden global IPv6 on secondary interfaces \
		if ip -6 addr show dev "$$IFACE" 2>/dev/null | grep -Eq 'inet6 2[0-9a-f]'; then \
			echo "❌ $$IFACE has a global IPv6 but must not"; exit 1; \
		fi; \
	done; \
	\
	echo "✅ IPv6 invariants OK"