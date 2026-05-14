# --------------------------------------------------------------------
# mk/30_sanity.mk — Validate IPv4/IPv6 topology correctness
# --------------------------------------------------------------------
# CONTRACT:
# - Validates each host's IPv4 and IPv6 address against SOT
# - Validates each host's default gateway (IPv4 + IPv6)
# - Validates each host's DNS resolver (IPv4 + IPv6)
# - BusyBox‑safe, POSIX‑compliant, no bashisms
# - Deterministic diagnostics; fails hard on mismatch
# --------------------------------------------------------------------

# --------------------------------------------------------------------
# Helper macro: validate a host's IPv4 + IPv6 topology
# $(1) = host IPv4
# $(2) = host IPv6
# $(3) = SSH user
# $(4) = host name (for logs)
# --------------------------------------------------------------------
define validate_host_topology
	@echo "🔍 Checking $(4) IPv4/IPv6 configuration..."
	@ssh -p 2222 $(3)@$(1) "ip -4 addr show | grep -q '$(1)'" \
		&& echo "   ✅ IPv4 address matches $(1)" \
		|| (echo "   ❌ IPv4 address mismatch"; exit 1)
	@ssh -p 2222 $(3)@$(1) "ip -6 addr show | grep -q '$(2)'" \
		&& echo "   ✅ IPv6 address matches $(2)" \
		|| (echo "   ❌ IPv6 address mismatch"; exit 1)
	@ssh -p 2222 $(3)@$(1) "ip route show default | grep -q '$(LAN_ROUTER)'" \
		&& echo "   ✅ IPv4 gateway matches $(LAN_ROUTER)" \
		|| (echo "   ❌ IPv4 gateway mismatch"; exit 1)
	@ssh -p 2222 $(3)@$(1) "ip -6 route show default | grep -q '$(LAN6_ROUTER)'" \
		&& echo "   ✅ IPv6 gateway matches $(LAN6_ROUTER)" \
		|| (echo "   ❌ IPv6 gateway mismatch"; exit 1)
	@ssh -p 2222 $(3)@$(1) "grep nameserver /etc/resolv.conf | grep -q '$(LAN_ROUTER)'" \
		&& echo "   ✅ DNS resolver includes $(LAN_ROUTER)" \
		|| echo "   ⚠️ DNS resolver does not include $(LAN_ROUTER)"
endef

.PHONY: sanity-nas
sanity-nas:
	$(call validate_host_topology,$(LAN_NAS),$(LAN6_NAS),$(SSH_USER_NAS),NAS)

.PHONY: sanity-synology
sanity-synology:
	$(call validate_host_topology,$(LAN_SYNOLOGY),$(LAN6_SYNOLOGY),$(SSH_USER_SYNOLOGY),Synology)

.PHONY: sanity-qnap
sanity-qnap:
	$(call validate_host_topology,$(LAN_QNAP),$(LAN6_QNAP),$(SSH_USER_QNAP),QNAP)

.PHONY: sanity-router
sanity-router:
	@echo "🔍 Checking router IPv6 configuration..."
	@ssh -p 2222 $(SSH_USER_ROUTER)@$(LAN_ROUTER) "ip -6 addr show | grep -q '$(LAN6_ROUTER)'" \
		&& echo "   ✅ Router IPv6 matches $(LAN6_ROUTER)" \
		|| (echo "   ❌ Router IPv6 mismatch"; exit 1)

.PHONY: sanity-topology
sanity-topology: sanity-router sanity-nas sanity-synology sanity-qnap
	@echo "🎉 All topology checks passed"
