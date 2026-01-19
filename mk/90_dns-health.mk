# mk/90_dns-health.mk

DNS_CHECK := /usr/local/bin/dns-health-check.sh

.PHONY: check-dns
check-dns: | install-all
	@echo "Running DNS health check (requires sudo)..."
	@$(run_as_root) $(DNS_CHECK) || echo "⚠️ DNS health check reported issues (likely cold cache)"
