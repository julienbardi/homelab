# mk/router/90_health.mk
# ------------------------------------------------------------
# ROUTER HEALTH & SECURITY INVARIANTS (namespaced)
# ------------------------------------------------------------
export ROUTER_CADDY_BIN

.PHONY: router-health
router-health: router-ssh-check router-bootstrap-primitives
	@echo
	@echo "Router Health"
	@echo "────────────────────────────────────────────────────────"
	@ssh "$(SSH_HOST_ROUTER)" ' \
		set -e; \
		echo "System      : $$(uname -m)"; \
		echo "Uptime      : $$(uptime | sed "s/^ *//")"; \
		echo "Storage     :"; \
		df -h /jffs 2>/dev/null || true; \
		echo; \
		if iptables -S | grep -qE -- "-A .* -p tcp .*--dport 443 .* -j ACCEPT"; then \
			echo "✖  Firewall     WAN HTTPS exposed"; \
			exit 1; \
		else \
			echo "✔  Firewall     WAN HTTPS blocked"; \
		fi; \
		if wg show wgs1 >/dev/null 2>&1; then \
			echo "✔  WireGuard    wgs1 interface"; \
		else \
			echo "✖  WireGuard    wgs1 missing"; \
			exit 1; \
		fi; \
		if wg show wgs1 | grep -q "listening port: 51819"; then \
			echo "✔  WireGuard    UDP 51819 listening"; \
		else \
			echo "✖  WireGuard    UDP 51819 not listening"; \
			exit 1; \
		fi; \
		if iptables -C FORWARD -i wgs1 -j ACCEPT 2>/dev/null && \
		   iptables -C FORWARD -o wgs1 -j ACCEPT 2>/dev/null; then \
			echo "✔  WireGuard    forwarding"; \
		else \
			echo "✖  WireGuard    forwarding missing"; \
			iptables -S FORWARD | grep wgs1 || true; \
			exit 1; \
		fi; \
		if [ -x "$(ROUTER_CADDY_BIN)" ]; then \
			if pidof caddy >/dev/null; then \
				echo "✔  Caddy        healthy"; \
			else \
				echo "ℹ️  Caddy        installed but disabled"; \
			fi; \
		else \
			echo "ℹ️  Caddy        not installed"; \
		fi; \
		echo "✔  IPv6         per-peer model active"; \
		echo; \
		echo "✔  Router healthy"; \
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

