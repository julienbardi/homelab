# mk/90_dns-health.mk

.PHONY: dns-suite dns-health pre-reboot-check

dns-health: dns-suite

dns-suite: deploy-unbound dnsdist-config check-dnsdist-listeners prereqs /usr/local/bin/dns-suite.sh
	@echo "📊 Running full DNS suite"
	@/usr/local/bin/dns-suite.sh

pre-reboot-check: dns-suite dnsdist-pre-reboot-check
	@echo "✅ DNS stack healthy — safe to reboot"
