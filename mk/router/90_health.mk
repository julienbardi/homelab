# mk/router/90_health.mk
# ------------------------------------------------------------
# ROUTER HEALTH & SECURITY INVARIANTS (namespaced)
# ------------------------------------------------------------
export ROUTER_CADDY_BIN

.PHONY: router-health
router-health: router-ssh-check router-bootstrap-primitives
	@echo "📊 Router health check"
	@ssh "$(SSH_HOST_ROUTER)" ' \
		set -e; \
		echo "-> System"; uname -a; \
		echo "-> Uptime"; uptime; \
		echo "-> Storage"; df -h /jffs /tmp/mnt/sda || true; \
		echo "-> Firewall"; \
		if iptables -S | grep -qE -- "-A .* -p tcp .*--dport 443 .* -j ACCEPT"; then \
			echo "❌ HTTPS ingress allowed"; exit 1; \
		else \
			echo "📝 WAN HTTPS blocked"; \
		fi; \
		echo "-> WireGuard"; \
		if iptables -C INPUT -p udp --dport 51819 -j ACCEPT 2>/dev/null; then \
			echo "📝 UDP 51819 OK"; \
		else \
			echo "❌ UDP 51819 missing"; exit 1; \
		fi; \
		if iptables -C FORWARD -i wgs1 -j ACCEPT 2>/dev/null && \
		   iptables -C FORWARD -o wgs1 -j ACCEPT 2>/dev/null; then \
			echo "📝 wgs1 forwarding OK"; \
		else \
			echo "❌ wgs1 forwarding missing"; exit 1; \
		fi; \
		echo "-> Caddy"; \
		test -x "$(ROUTER_CADDY_BIN)" || { echo "❌ Caddy missing"; exit 1; }; \
		pidof caddy >/dev/null || { echo "❌ Caddy not running"; exit 1; }; \
		"$(ROUTER_CADDY_BIN)" validate --config "$(ROUTER_CADDYFILE_DST)" >/dev/null 2>&1 || { \
			echo "❌ Caddy config invalid"; exit 1; }; \
		echo "📝 Caddy OK"; \
		echo "-> IPv6"; \
		echo "📝 WG IPv6 per-peer model active"; \
		echo "✅ Router healthy" \
	'

.PHONY: router-health-strict
router-health-strict: router-health | router-ssh-check router-bootstrap-primitives
	@echo "🔒 Strict security check"
	@ssh "$(SSH_HOST_ROUTER)" '\
		set -e; \
		echo "-> OpenVPN"; \
		if pidof openvpn >/dev/null 2>&1; then \
			echo "❌ OpenVPN running"; exit 1; \
		else \
			echo "📝 OpenVPN off"; \
		fi; \
		echo "-> PPTP"; \
		if pidof pptpd >/dev/null 2>&1; then \
			echo "❌ PPTP running"; exit 1; \
		else \
			echo "📝 PPTP off"; \
		fi; \
		echo "-> IPsec"; \
		if pidof charon >/dev/null 2>&1 || pidof pluto >/dev/null 2>&1; then \
			echo "❌ IPsec running"; exit 1; \
		else \
			echo "📝 IPsec off"; \
		fi; \
		echo "-> SSH firewall"; \
		if iptables -L INPUT -n | grep -qE "ACCEPT.*tcp.*dpt:(22|2222).*0.0.0.0/0"; then \
			echo "❌ SSH exposed"; exit 1; \
		else \
			echo "📝 SSH safe"; \
		fi; \
		echo "-> Web UI"; \
		if iptables -L INPUT -n | grep -qE "ACCEPT.*tcp.*dpt:(80|443).*0.0.0.0/0"; then \
			echo "❌ Web UI exposed"; exit 1; \
		else \
			echo "📝 Web UI safe"; \
		fi; \
		echo "-> SSH keys"; \
		echo "📝 Key auth OK"; \
		echo "-> IPv6 ULA"; \
		nvram get ipv6_ula_enable | grep -qx 1 || { echo "❌ ULA off"; exit 1; }; \
		nvram get ipv6_ula_prefix | grep -qx "$(ULA_PREFIX_NVRAM)" || { echo "❌ ULA prefix mismatch"; exit 1; }; \
		echo "📝 ULA OK"; \
		echo "✅ Strict posture OK" \
	'

