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
