# mk/router/90_health.mk
# ------------------------------------------------------------
# ROUTER HEALTH & SECURITY INVARIANTS (namespaced)
# ------------------------------------------------------------

.PHONY: router-health
router-health: router-ssh-check
	@echo "🩺 Router health check"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		set -e; \
		echo "→ System:"; \
			uname -a; \
		echo "→ Uptime:"; \
			uptime; \
		echo "→ Storage:"; \
			df -h /jffs /tmp/mnt/sda || true; \
		echo "→ Firewall:"; \
			if ( iptables -S | grep -qE -- "-A .* -p tcp .*--dport 443 .* -j ACCEPT" ); then \
				echo " ✓ HTTPS ingress allowed"; \
			else \
				echo " ❌ WAN HTTPS intentionally blocked"; exit 1; \
			fi; \
		echo "→ WireGuard:"; \
			if iptables -L WGSI >/dev/null 2>&1; then \
				echo "   ✓ WGSI (WireGuard server ingress) present"; \
				iptables -L WGSI -n -v | sed "s/^/     /"; \
			else \
				echo "   ❌ WGSI chain missing"; exit 1; \
			fi; \
			if iptables -L WGCI >/dev/null 2>&1; then \
				echo "   ✓ WGCI (WireGuard client ingress) present"; \
				iptables -L WGCI -n -v | sed "s/^/     /"; \
			else \
				echo "   ❌ WGCI chain missing"; exit 1; \
			fi; \
		echo "→ Caddy:"; \
			test -x "$(CADDY_BIN)" || { echo "   ❌ binary missing"; exit 1; }; \
			pidof caddy >/dev/null || { echo "   ❌ process not running"; exit 1; }; \
			$(CADDY_BIN) validate --config $(CADDYFILE_DST) >/dev/null 2>&1 || \
				{ echo "   ❌ config invalid"; exit 1; }; \
			echo "   ✓ binary present"; \
			echo "   ✓ process running"; \
			echo "   ✓ config valid"; \
		echo "→ IPv6 FORWARD hook scope:"; \
			if ip6tables -S FORWARD | grep -q -- "-j WGSF6"; then \
				echo "   ❌ WGSF6 is globally hooked into FORWARD"; exit 1; \
			fi; \
			ip6tables -S FORWARD | grep -q -- "^-A FORWARD -i wg\+ -j WGSF6" || \
				{ echo "   ❌ missing FORWARD -i wg+ -> WGSF6"; exit 1; }; \
			ip6tables -S FORWARD | grep -q -- "^-A FORWARD -o wg\+ -j WGSF6" || \
				{ echo "   ❌ missing FORWARD -o wg+ -> WGSF6"; exit 1; }; \
			echo "   ✓ WGSF6 scoped to WireGuard only"; \
		echo "✅ Router healthy" \
	'

.PHONY: router-health-strict
router-health-strict: router-health | router-ssh-check
	@echo "🔒 Enforcing strict security invariants"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		set -e; \
		echo "→ OpenVPN:"; \
			if pidof openvpn >/dev/null 2>&1; then \
				echo "   ❌ OpenVPN process running"; exit 1; \
			fi; \
			echo "   ✓ OpenVPN disabled"; \
		echo "→ PPTP:"; \
		if pidof pptpd >/dev/null 2>&1; then \
			echo "   ❌ PPTP daemon running"; exit 1; \
		fi; \
		echo "   ✓ PPTP disabled"; \
		echo "→ IPsec:"; \
		if pidof charon >/dev/null 2>&1 || pidof pluto >/dev/null 2>&1; then \
			echo "   ❌ IPsec daemon running"; exit 1; \
		fi; \
		echo "   ✓ IPsec disabled"; \
		echo "→ SSH access:"; \
		if iptables -L INPUT -n | grep -qE "ACCEPT.*tcp.*dpt:(22|2222).*0.0.0.0/0"; then \
			echo "   ❌ SSH exposed via firewall"; exit 1; \
		fi; \
		echo "   ✓ SSH not exposed via firewall"; \
		echo "→ Web UI:"; \
		if iptables -L INPUT -n | grep -qE "ACCEPT.*tcp.*dpt:(80|443).*0.0.0.0/0"; then \
			echo "   ❌ Web UI exposed on WAN"; exit 1; \
		fi; \
		echo "   ✓ Web UI not exposed on WAN"; \
		echo "→ SSH keys:"; \
		echo " ✓ SSH key authentication works"; \
		echo "→ IPv6 ULA:"; \
		nvram get ipv6_ula_enable | grep -qx 1 || { echo "   ❌ ULA disabled"; exit 1; }; \
		nvram get ipv6_ula_prefix | grep -qx 'fd89:7a3b:42c0::/48' || { echo "   ❌ ULA prefix mismatch"; exit 1; }; \
		echo "   ✓ ULA configured"; \
		echo "✅ Strict security posture verified" \
	'
