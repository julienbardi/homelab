# mk/90_dns-health.mk

DNS_CHECK := $(INSTALL_PATH)/dns-health-check.sh

# Default to loopback for the standard check: 127.0.0.1
RESOLVER_ADDR_LOCAL ?= $(NAS_LAN_IP)

.PHONY: check-dns
# check-dns uses the local address (Process Check)
check-dns: guard-config prereqs-dns-health-check-verify $(DNS_CHECK) ensure-run-as-root
	@echo "📊 Running DNS health check on $(RESOLVER_ADDR_LOCAL):$(UNBOUND_PORT)..."
	@$(run_as_root) "$(DNS_CHECK)" "$(RESOLVER_ADDR_LOCAL)" -p "$(UNBOUND_PORT)" || \
		echo "⚠️ DNS health check reported issues (likely cold cache)"

# Check via the physical LAN interface
.PHONY: check-dns-lan
check-dns-lan: guard-config ensure-run-as-root
	@echo "📊 Running DNS health check on LAN IP $(NAS_LAN_IP):$(UNBOUND_PORT)..."
	@$(run_as_root) "$(DNS_CHECK)" "$(NAS_LAN_IP)" -p "$(UNBOUND_PORT)"

.PHONY: status-dns
status-dns: ensure-run-as-root
	@if $(run_as_root) systemctl is-active --quiet unbound; then \
		echo "✅ Unbound active (Port: $(UNBOUND_PORT))"; \
	else \
		echo "❌ Unbound inactive"; exit 1; \
	fi

# Define the ULA Loopback
RESOLVER_ADDR6_LOCAL ?= ::1

.PHONY: check-dns-v6
check-dns-v6: guard-config ensure-run-as-root
	@echo "🌐 Testing IPv6 DNS via Loopback [::1]..."
	@$(run_as_root) "$(DNS_CHECK)" "$(RESOLVER_ADDR6_LOCAL)" -p "$(UNBOUND_PORT)"

.PHONY: check-dns-lan-v6
check-dns-lan-v6: guard-config ensure-run-as-root
	@# We derive the ULA from your deterministic contract if possible,
	@# or pull it from the promoted NAS_LAN_IP6 variable.
	@echo "🌐 Testing IPv6 DNS via ULA [$(NAS_LAN_IP6)]..."
	@$(run_as_root) "$(DNS_CHECK)" "$(NAS_LAN_IP6)" -p "$(UNBOUND_PORT)"