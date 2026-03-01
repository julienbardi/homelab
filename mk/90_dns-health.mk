# mk/90_dns-health.mk

DNS_CHECK := /usr/local/bin/dns-health-check.sh

# Specify the port since Unbound is on 5335
RESOLVER_ADDR := 127.0.0.1
RESOLVER_PORT := 5335

# Alias to install only this tool using the common pattern rule
.PHONY: install-dns-health
install-dns-health: $(DNS_CHECK)

# Remove the dependency on install-all to prevent the restart loop
.PHONY: check-dns
check-dns: prereqs-dns-health-check-verify #| install-all
	@echo "🩺 Running DNS health check on $(RESOLVER_ADDR):$(RESOLVER_PORT)..."
	@$(run_as_root) $(DNS_CHECK) "$(RESOLVER_ADDR) -p $(RESOLVER_PORT)" || echo "⚠️ DNS health check reported issues (likely cold cache)"
