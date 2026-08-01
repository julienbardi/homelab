# mk/prereqs-network.mk
# ------------------------------------------------------------
# Network readiness, DNS bootstrap, DNS warmers, public DNS verify
# ------------------------------------------------------------

prereqs-network-verify:
	@command -v wg >/dev/null || { echo "❌ wireguard missing"; exit 1; }
ifeq ($(ROLE),router)
	@command -v ethtool >/dev/null || { \
		echo "❌ ethtool missing (required for ROLE=router)"; exit 1; }
	@sysctl net.ipv4.ip_forward >/dev/null 2>&1 || \
		echo "⚠️  Cannot read net.ipv4.ip_forward (sysctl unavailable?)"
else
	@command -v ethtool >/dev/null || \
		echo "ℹ️  ethtool not required for ROLE=$(ROLE)"
endif

prereqs-public-dns-verify: | ensure-host-default-route
	@$(call WITH_SECRETS, sh -c '\
		echo "🔍 Verifying public DNS CNAME for apt.bardi.ch"; \
		out=$$(dig +short @$$PUBLIC_DNS apt.bardi.ch CNAME 2>&1); \
		case "$$out" in \
			*"network unreachable"*) \
				echo "❌ Network unreachable: NAS has no default route"; \
				exit 1;; \
			*"no servers could be reached"*) \
				echo "❌ Cannot reach DNS server $$PUBLIC_DNS"; \
				exit 1;; \
			*"connection timed out"*) \
				echo "❌ DNS query to $$PUBLIC_DNS timed out"; \
				exit 1;; \
		esac; \
		cname=$$(printf "%s" "$$out" | sed "s/\\.$$//"); \
		if [ -z "$$cname" ]; then \
			echo "❌ ERROR: No CNAME returned for apt.bardi.ch"; \
			exit 1; \
		fi; \
		if [ "$$cname" != "$$APT_CNAME_EXPECTED" ]; then \
			echo "❌ ERROR: Public DNS misconfiguration detected"; \
			exit 1; \
		fi; \
		echo "✅ Public DNS CNAME is correct"; \
	')

prereqs-tailscale-repo-verify: | ensure-host-default-route
	@echo "🔍 Verifying Tailscale repo hygiene"
	@if [ -f $(TAILSCALE_REPO_FILE) ]; then \
		bad=$$(grep -Rl "pkgs.tailscale.com" /etc/apt/sources.list.d \
			| xargs -r grep -L "signed-by=$(TAILSCALE_KEYRING)"); \
		if [ -n "$$bad" ]; then \
			echo "❌ Tailscale repo missing signed-by=$(TAILSCALE_KEYRING)"; \
			exit 1; \
		fi; \
	fi
	@echo "✅ Tailscale repo hygiene check passed"

ensure-bootstrap-dns:
	@echo "🔍 Checking bootstrap DNS..."
	@set -euo pipefail; \
	ready=0; \
	for i in 1 2 3 4 5 6 7 8 9 10; do \
		if dig @$(LAN_ROUTER) "$(DOMAIN)" +short +tries=1 +time=1 >/dev/null 2>&1; then \
			ready=1; break; fi; \
		sleep 0.5; \
	done; \
	if [ "$$ready" -eq 1 ]; then \
		echo "✅ Bootstrap DNS reachable via router ($(LAN_ROUTER))"; \
		exit 0; \
	fi; \
	echo "⚠️ Bootstrap DNS unreachable, checking fallback..."; \
	if command -v resolvectl >/dev/null 2>&1; then \
		if resolvectl query "$(DOMAIN)" >/dev/null 2>&1; then \
			echo "✅ Fallback DNS OK via systemd-resolved"; exit 0; \
		else echo "❌ Fallback DNS failed"; exit 1; fi; \
	fi; \
	ns="$$(awk '/^nameserver/ {print $$2}' /etc/resolv.conf | head -n1)"; \
	if [ -z "$$ns" ]; then \
		echo "⚠️ Injecting router DNS"; \
		echo "nameserver $(LAN_ROUTER)" | $(run_as_root) tee /etc/resolv.conf >/dev/null; \
		ns="$(LAN_ROUTER)"; \
	fi; \
	if dig @"$$ns" "$(DOMAIN)" +short +tries=1 +time=2 >/dev/null 2>&1; then \
		echo "✅ Fallback DNS OK via /etc/resolv.conf"; exit 0; \
	fi; \
	if [ "$$ns" = "$(LAN_ROUTER)" ]; then \
		echo "⚠️ Injecting Cloudflare DNS"; \
		echo "nameserver $(PUBLIC_DNS)" | $(run_as_root) tee /etc/resolv.conf >/dev/null; \
		ns="$(PUBLIC_DNS)"; \
		if dig @"$$ns" "$(DOMAIN)" +short +tries=1 +time=2 >/dev/null 2>&1; then \
			echo "✅ Fallback DNS OK via Cloudflare"; exit 0; \
		fi; \
	fi; \
	echo "❌ No working DNS resolver found"; exit 1

ensure-dnsmasq-ready:
	@echo "⏳ Waiting for dnsmasq..."
	@ssh $(SSH_HOST_ROUTER) '/jffs/scripts/dnsmasq-ready.sh'
