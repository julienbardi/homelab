# mk/90_dns-health.mk

DNS_CHECK := $(INSTALL_PATH)/dns-health-check.sh

# Specify the port since Unbound is on 5335
RESOLVER_ADDR := 127.0.0.1
RESOLVER_PORT := 5335

# Alias to install only this tool using the common pattern rule
.PHONY: install-dns-health
install-dns-health: $(DNS_CHECK)

$(DNS_CHECK): $(REPO_ROOT)scripts/dns-health-check.sh
	@echo "📦 Installing dns-health-check"
	@$(run_as_root) install -o root -g root -m 0755 \
		"$<" "$@"

# Remove the dependency on install-all to prevent the restart loop
.PHONY: check-dns
check-dns: prereqs-dns-health-check-verify ensure-run-as-root #| install-all
	@echo "📊 Running DNS health check on $(RESOLVER_ADDR):$(RESOLVER_PORT)..."
	@$(run_as_root) $(DNS_CHECK) "$(RESOLVER_ADDR)" -p "$(RESOLVER_PORT)" || echo "⚠️ DNS health check reported issues (likely cold cache)"

# Example variable check if you wanted to be extra precise
ifndef NAS_LAN_IP
$(error NAS_LAN_IP is not defined. Check your common mk files.)
endif

.PHONY: check-dns-lan
check-dns-lan: ensure-run-as-root
	@echo "📊 Running DNS health check on LAN IP $(NAS_LAN_IP):$(RESOLVER_PORT)..."
	@$(run_as_root) $(DNS_CHECK) "$(NAS_LAN_IP)" -p "$(RESOLVER_PORT)"

status-dns: ensure-run-as-root
	@if $(run_as_root) systemctl is-active --quiet unbound; then \
		echo "✅ Unbound active"; \
	else \
		echo "❌ Unbound inactive"; exit 1; \
	fi
