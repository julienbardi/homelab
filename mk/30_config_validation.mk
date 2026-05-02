# 30_config-validation.mk

# ------------------------------------------------------------
# DNS policy & split-horizon invariants
# ------------------------------------------------------------
# Contract:
# - hosts defines all hostnames treated as internal by Caddy
# - Every INTERNAL_HOST must resolve via Unbound to a private IP
# - Public DNS must never expose private IPs
# - dns-preflight enforces these invariants

CADDY_INTERNAL_HOSTS_SRC := $(REPO_ROOT)config/caddy/internal-hosts.txt

.PHONY: dns-preflight assert-tailnet check-public-dns check-caddy-internal-hosts

dns-preflight: \
	assert-tailnet \
	check-public-dns \
	check-caddy-internal-hosts \
	check-dnsmasq-udp-buffers

assert-tailnet:
	@tailscale status >/dev/null 2>&1 || \
		( echo "❌ Tailnet not connected — run: make tailnet"; exit 1 )

check-public-dns:
	@echo "🔍 Verifying public CNAMEs resolving to canonical names"
	@test -f $(CADDY_INTERNAL_HOSTS_SRC) || \
		( echo "❌ Missing $(CADDY_INTERNAL_HOSTS_SRC)"; exit 1 )
	@hosts=$$(sed '/^\s*#/d;/^\s*$$/d' $(CADDY_INTERNAL_HOSTS_SRC)); \
	for host in $$hosts; do \
		cname=$$(dig @1.1.1.1 $$host CNAME +short | sed '/^$$/d'); \
		if [ -z "$$cname" ]; then \
			echo "❌ $$host must resolve to exactly one CNAME record"; \
			echo "👉 Define public DNS CNAME in Infomaniak"; exit 1; \
		fi; \
		if printf "%s" "$$cname" | grep -vqE '\.bardi\.ch\.?$$'; then \
			echo "❌ $$host CNAME target is incorrect: $$cname"; \
			echo "👉 Must point to canonical *.bardi.ch target"; \
			exit 1; \
		fi; \
	done
	@echo "✅ All public DNS CNAMEs defined"

check-caddy-internal-hosts:
	@echo "🔍 Verifying Caddy internal hosts"
	@test -n "$(CADDY_INTERNAL_HOSTS_FILE)" || \
		( echo "❌ CADDY_INTERNAL_HOSTS_FILE is not defined"; exit 1 )
	@test -f $(CADDY_INTERNAL_HOSTS_FILE) || \
		( echo "❌ Missing $(CADDY_INTERNAL_HOSTS_FILE)"; exit 1 )
	@test -f $(CADDY_INTERNAL_HOSTS_SRC) || \
		( echo "❌ Missing $(CADDY_INTERNAL_HOSTS_SRC)"; exit 1 )
	@hosts=$$(sed '/^\s*#/d;/^\s*$$/d' $(CADDY_INTERNAL_HOSTS_SRC)); \
	for host in $$hosts; do \
		if ! grep -qx "$$host" $(CADDY_INTERNAL_HOSTS_FILE); then \
			echo "❌ $$host is internal but not restricted in Caddy"; \
			echo "👉 Add it to $(CADDY_INTERNAL_HOSTS_FILE)"; \
			exit 1; \
		fi; \
	done
	@echo "✅ All internal hosts are explicitly restricted in Caddy"

.PHONY: assert-unbound-running assert-dnsmasq-running

assert-unbound-running:
	@systemctl is-active --quiet unbound || \
		( echo "❌ Unbound is not running"; exit 1 )

assert-dnsmasq-running:
	@systemctl is-active --quiet dnsmasq || \
		( echo "❌ dnsmasq is not running"; exit 1 )

.PHONY: dns-postflight check-unbound-internal-resolution

dns-postflight: \
	assert-unbound-running \
	assert-dnsmasq-running \
	assert-dnsdist-running \
	check-unbound-internal-resolution \
	dns-runtime-check \
	check-dnsdist-doh-local

check-unbound-internal-resolution:
	@echo "🧩 Verifying Unbound resolves internal hosts to private IPs"
	@command -v dig >/dev/null || \
		( echo "❌ dig not available"; exit 1 )
	@test -f $(CADDY_INTERNAL_HOSTS_SRC) || \
		( echo "❌ Missing $(CADDY_INTERNAL_HOSTS_SRC)"; exit 1 )
	@hosts=$$(sed '/^\s*#/d;/^\s*$$/d' $(CADDY_INTERNAL_HOSTS_SRC)); \
	for host in $$hosts; do \
		ip=$$(dig @127.0.0.1 $$host A +short +time=3 +tries=1 | sed '/^$$/d'); \
		if [ -z "$$ip" ]; then \
			echo "❌ $$host did not resolve via Unbound within 3s"; \
			exit 1; \
		fi; \
		if ! echo "$$ip" | grep -Eq '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)'; then \
			echo "❌ $$host resolved to non-private IP via Unbound: $$ip"; \
			exit 1; \
		fi; \
		aaaa=$$(dig @127.0.0.1 $$host AAAA +short +time=3 +tries=1 | sed '/^$$/d'); \
		if [ -n "$$aaaa" ]; then \
			echo "❌ $$host leaked AAAA record via Unbound: $$aaaa"; \
			exit 1; \
		fi; \
	done
	@echo "✅ All internal hosts resolve to private IPs via Unbound"
