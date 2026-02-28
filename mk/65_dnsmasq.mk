# mk/65_dnsmasq.mk

.PHONY: enable-dnsmasq
enable-dnsmasq: \
	assert-unbound-running \
	install-pkg-dnsmasq \
	deploy-dnsmasq-config
	@echo "🔄 Restarting dnsmasq (Unbound backend verified)"
	@$(run_as_root) systemctl restart dnsmasq
	@$(run_as_root) systemctl is-active --quiet dnsmasq || \
	    ( echo "❌ dnsmasq failed to start"; exit 1 )
	@echo "✅ dnsmasq running with Unbound backend"
