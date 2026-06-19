# mk/18_ipv6-invariants.mk
# --------------------------------------------------------------------
# CONTRACT:
# - Ensures IPv6 topology matches homelab design.
# - eth0: MUST have ULA always.
# - eth0: MUST have GUA + default route only when router delegates a prefix.
# - eth1: MUST NOT have global IPv6 (if present).
# --------------------------------------------------------------------

.PHONY: verify-ipv6-invariants

verify-ipv6-invariants:
	@set -eu; \
	echo "🔍 Verifying IPv6 invariants..."; \
	\
	# eth0 MUST have a ULA (fdxx::)
	if ! ip -6 addr show dev eth0 | grep -Eq 'inet6 fd[0-9a-f]'; then \
		echo "❌ eth0 missing ULA IPv6 address"; exit 1; \
	fi; \
	\
	# Detect if eth0 has a global IPv6 (2xxx::)
	HAS_GUA=$$(ip -6 addr show dev eth0 | grep -Eq 'inet6 2[0-9a-f]' && echo yes || echo no); \
	\
	if [ "$$HAS_GUA" = "yes" ]; then \
		# If GUA exists, default route MUST exist
		if ! ip -6 route show default | grep -q 'dev eth0'; then \
			echo "❌ eth0 has global IPv6 but no default IPv6 route"; exit 1; \
		fi; \
		echo "✅ eth0: GUA + default IPv6 route OK"; \
	else \
		echo "ℹ️ eth0 has no global IPv6 — skipping default route check (router not delegating prefix)"; \
	fi; \
	\
	# eth1 MUST NOT have a global IPv6 (only check if eth1 exists)
	if [ -d /sys/class/net/eth1 ]; then \
		if ip -6 addr show dev eth1 | grep -Eq 'inet6 (2|fd)[0-9a-f]'; then \
			echo "❌ eth1 has a global IPv6 but must not"; exit 1; \
		fi; \
	fi; \
	\
	echo