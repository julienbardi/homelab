# mk/90_dns-health.mk

.PHONY: dns-suite dns-health

dns-health: dns-suite

dns-suite: /usr/local/bin/dns-suite.sh
	@echo "📊 Running full DNS suite"
	@/usr/local/bin/dns-suite.sh
