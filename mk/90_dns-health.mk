# mk/90_dns-health.mk — Clean, privilege‑correct, no drift

DNS_CHECK := $(INSTALL_PATH)/dns-health-check.sh

# Unbound listens on loopback:5335
RESOLVER_ADDR_LOCAL ?= 127.0.0.1
RESOLVER_ADDR6_LOCAL ?= ::1

# -------------------------------
# Primary health check (IPv4)
# -------------------------------
.PHONY: check-dns
check-dns: prereqs-dns-health-check-verify $(DNS_CHECK)
	@echo "📊 Running DNS health check on $(RESOLVER_ADDR_LOCAL):$(UNBOUND_PORT)..."
	@$(run_as_root) "$(DNS_CHECK)" "$(RESOLVER_ADDR_LOCAL)" -p "$(UNBOUND_PORT)" || \
		echo "⚠️ DNS health check reported issues (likely cold cache)"


# -------------------------------
# LAN IPv4 check
# -------------------------------
.PHONY: check-dns-lan
check-dns-lan: ensure-run-as-root
	@echo "📊 Running DNS health check on LAN IP $(NAS_LAN_IP):$(UNBOUND_PORT)..."
	@$(run_as_root) "$(DNS_CHECK)" "$(NAS_LAN_IP)" -p "$(UNBOUND_PORT)"

# -------------------------------
# IPv6 loopback check (only if supported)
# -------------------------------
.PHONY: check-dns-v6
check-dns-v6: ensure-run-as-root
	@if [ -z "$(RESOLVER_ADDR6_LOCAL)" ] || [ "$(RESOLVER_ADDR6_LOCAL)" = "disabled" ]; then \
		echo "ℹ️ IPv6 loopback not available — skipping"; \
		exit 0; \
	fi
	@echo "🌐 Testing IPv6 DNS via Loopback [$(RESOLVER_ADDR6_LOCAL)]..."
	@$(run_as_root) "$(DNS_CHECK)" "$(RESOLVER_ADDR6_LOCAL)" -p "$(UNBOUND_PORT)"

# -------------------------------
# IPv6 LAN check (only if NAS_LAN_IP6 exists)
# -------------------------------
.PHONY: check-dns-lan-v6
check-dns-lan-v6: ensure-run-as-root
	@if [ -z "$(NAS_LAN_IP6)" ]; then \
		echo "ℹ️ No IPv6 LAN address configured — skipping"; \
		exit 0; \
	fi
	@echo "🌐 Testing IPv6 DNS via ULA [$(NAS_LAN_IP6)]..."
	@$(run_as_root) "$(DNS_CHECK)" "$(NAS_LAN_IP6)" -p "$(UNBOUND_PORT)"

# -------------------------------
# Unbound status
# -------------------------------
.PHONY: status-dns
status-dns: ensure-run-as-root
	@if systemctl is-active --quiet unbound; then \
		echo "✅ Unbound active (Port: $(UNBOUND_PORT))"; \
	else \
		echo "❌ Unbound inactive"; exit 1; \
	fi
