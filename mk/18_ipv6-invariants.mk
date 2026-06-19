# mk/18_ipv6-invariants.mk
# --------------------------------------------------------------------
# CONTRACT:
# - Ensures IPv6 topology matches homelab design.
# - eth0: MUST have global IPv6 + default route.
# - eth1: MUST NOT have global IPv6 (if present).
# --------------------------------------------------------------------

.PHONY: verify-ipv6-invariants

verify-ipv6-invariants:
	@set -eu; \
	echo "🔍 Verifying IPv6 invariants..."; \
	\
	# eth0 MUST have a global IPv6 (2xxx:: or fdxx::)
	if ! ip -6 addr show dev eth0 | grep -Eq 'inet6 (2|fd)[0-9a-f]'; then \
		echo "❌ eth0 missing global IPv6 address"; exit 1; \
	fi; \
	\
	# eth0 MUST have a default IPv6 route
	if ! ip -6 route show default | grep -q 'dev eth0'; then \
		echo "❌ eth0 missing default IPv6 route"; exit 1; \
	fi; \
	\
	# eth1 MUST NOT have a global IPv6 (only check if eth1 exists)
	if [ -d /sys/class/net/eth1 ]; then \
		if ip -6 addr show dev eth1 | grep -Eq 'inet6 (2|fd)[0-9a-f]'; then \
			echo "❌ eth1 has a global IPv6 but must not"; exit 1; \
		fi; \
	fi; \
	\
	echo "✅ IPv6 invariants satisfied."
