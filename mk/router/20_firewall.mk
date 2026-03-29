# mk/router/20_firewall.mk
# ------------------------------------------------------------
# ROUTER FIREWALL & DNSMASQ CONVERGENCE (namespaced)
# ------------------------------------------------------------

.NOTPARALLEL: router-firewall-install

# ------------------------------------------------------------
# Firewall script deployment
# ------------------------------------------------------------

.PHONY: router-firewall-install
router-firewall-install: | router-ssh-check router-require-run-as-root
	@$(INSTALL_FILE_IF_CHANGED) "" "" $(SRC_SCRIPTS)/firewall-start \
		$(ROUTER_HOST) $(ROUTER_SSH_PORT) /jffs/scripts/firewall-start \
		"$(ROUTER_SCRIPTS_OWNER)" "$(ROUTER_SCRIPTS_GROUP)" 0755 \
		|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]

# ------------------------------------------------------------
# Firewall runtime assertions
# ------------------------------------------------------------

.PHONY: router-firewall-base-running
router-firewall-base-running: | router-ssh-check
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		iptables -L INPUT >/dev/null 2>&1 || \
		{ echo "❌ Base firewall not running"; exit 1; } \
	'

.PHONY: router-firewall-skynet-running
router-firewall-skynet-running: router-firewall-install router-firewall-base-running | router-ssh-check
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		set -e; \
		echo "→ Skynet firewall:"; \
		iptables -L SDN_FI >/dev/null 2>&1 || \
			{ echo "   ❌ Skynet INPUT chain missing"; exit 1; }; \
		iptables -L SDN_FF >/dev/null 2>&1 || \
			{ echo "   ❌ Skynet FORWARD chain missing"; exit 1; }; \
		iptables -L INPUT -n | grep -q "SDN_FI" || \
			{ echo "   ❌ Skynet INPUT chain not referenced"; exit 1; }; \
		iptables -L FORWARD -n | grep -q "SDN_FF" || \
			{ echo "   ❌ Skynet FORWARD chain not referenced"; exit 1; }; \
		echo "   ✓ Skynet chains present and active" \
	'

.PHONY: router-firewall-started
router-firewall-started: router-firewall-base-running

# ------------------------------------------------------------
# IPv6 forwarding enforcement (WireGuard scope)
# ------------------------------------------------------------

.PHONY: router-firewall-ipv6-forwarding
router-firewall-ipv6-forwarding: | router-ssh-check
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		set -e; \
		echo "→ IPv6 forwarding (WireGuard scope):"; \
		ip6tables -S WGSF6 >/dev/null 2>&1 || \
			{ echo "   ❌ WGSF6 chain missing"; exit 1; }; \
		ip6tables -S FORWARD | grep -q -- "^-A FORWARD -i wg\\+ -j WGSF6" || \
			{ echo "   ❌ missing FORWARD -i wg+ → WGSF6"; exit 1; }; \
		ip6tables -S FORWARD | grep -q -- "^-A FORWARD -o wg\\+ -j WGSF6" || \
			{ echo "   ❌ missing FORWARD -o wg+ → WGSF6"; exit 1; }; \
		if ip6tables -S FORWARD | grep -q -- "^-A FORWARD -j WGSF6"; then \
			echo "   ❌ WGSF6 is globally hooked into FORWARD"; exit 1; \
		fi; \
		ip6tables -S WGSF6 | tail -n1 | grep -qx -- "-A WGSF6 -j DROP" || \
			{ echo "   ❌ WGSF6 missing terminal DROP"; exit 1; }; \
		echo "   ✓ IPv6 forwarding enforced (WireGuard-only)" \
	'

# ------------------------------------------------------------
# Hardened firewall entrypoint
# ------------------------------------------------------------

.PHONY: router-firewall-hardened
router-firewall-hardened: \
	router-firewall-started \
	router-firewall-skynet-running \
	router-firewall-ipv6-forwarding
	@echo "🛡️ Firewall hardened and actively blocking threats"

# ------------------------------------------------------------
# Convenience aliases
# ------------------------------------------------------------

.PHONY: router-firewall
router-firewall: router-firewall-skynet-running

.PHONY: router-firewall-audit
router-firewall-audit: | router-ssh-check
	@echo "🔍 Router firewall audit"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		iptables  -S INPUT; \
		iptables  -S FORWARD; \
		ip6tables -S INPUT; \
		ip6tables -S FORWARD; \
		wg show \
	'

.PHONY: router-wg-health-strict
router-wg-health-strict: | router-ssh-check
	@echo "🔒 WireGuard strict health check"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		set -e; \
		echo "→ IPv4 policy chain:"; \
		iptables -S WGSF >/dev/null || \
			{ echo "❌ WGSF missing"; exit 1; }; \
		iptables -S WGSF | tail -n1 | grep -qx -- "-A WGSF -j DROP" || \
			{ echo "❌ WGSF missing terminal DROP"; exit 1; }; \
		echo "   ✓ WGSF OK"; \
		echo; \
		echo "→ IPv6 policy chain:"; \
		ip6tables -S WGSF6 >/dev/null || \
			{ echo "❌ WGSF6 missing"; exit 1; }; \
		ip6tables -S WGSF6 | tail -n1 | grep -qx -- "-A WGSF6 -j DROP" || \
			{ echo "❌ WGSF6 missing terminal DROP"; exit 1; }; \
		echo "   ✓ WGSF6 OK"; \
		echo; \
		echo "→ FORWARD hooks (scoped):"; \
		iptables  -S FORWARD | grep -q -- "-i wg\\+ -j WGSF" || \
			{ echo "❌ missing IPv4 wg → WGSF hook"; exit 1; }; \
		ip6tables -S FORWARD | grep -q -- "-i wg\\+ -j WGSF6" || \
			{ echo "❌ missing IPv6 wg → WGSF6 hook"; exit 1; }; \
		if iptables -S FORWARD | grep -q -- "-j WGSF"; then \
			echo "❌ WGSF globally hooked into FORWARD"; exit 1; \
		fi; \
		if ip6tables -S FORWARD | grep -q -- "-j WGSF6"; then \
			echo "❌ WGSF6 globally hooked into FORWARD"; exit 1; \
		fi; \
		echo "   ✓ FORWARD hooks scoped correctly"; \
	'
