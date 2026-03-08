# mk/router/firewall.mk
# ------------------------------------------------------------
# ROUTER FIREWALL & DNSMASQ CONVERGENCE
# ------------------------------------------------------------
#
# Responsibilities:
#   - dnsmasq cache configuration
#   - Firewall script deployment
#   - Firewall runtime assertions
#   - IPv6 forwarding enforcement (WireGuard scope)
#
# Contracts:
#   - Owns all firewall-related router artifacts
#   - MUST NOT overlap ownership with other modules
#   - MUST be safe under 'make -j'
# ------------------------------------------------------------
.NOTPARALLEL: \
	dnsmasq-cache \
	firewall-install

.PHONY: dnsmasq-cache
dnsmasq-cache: | ssh-check
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		set -e; \
		mkdir -p /jffs/configs; \
		touch $(DNSMASQ_CONF_ADD); \
		if grep -qx "$(DNSMASQ_CACHE_LINE)" $(DNSMASQ_CONF_ADD); then \
			echo "dnsmasq cache OK"; \
		else \
			tmp="$(DNSMASQ_CONF_ADD).tmp.$$"; \
			printf "%s\n" "$(DNSMASQ_CACHE_LINE)" > "$$tmp"; \
			mv -f "$$tmp" "$(DNSMASQ_CONF_ADD)"; \
			service restart_dnsmasq; \
		fi \
	'

.PHONY: firewall-install
firewall-install: | ssh-check require-run-as-root
	$(call deploy_if_changed,\
		$(SRC_SCRIPTS)/firewall-start,\
		/jffs/scripts/firewall-start)

.PHONY: firewall-base-running
firewall-base-running: | ssh-check
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		iptables -L INPUT >/dev/null 2>&1 || \
		{ echo "❌ Base firewall not running"; exit 1; } \
	'

#  asserts observed enforcement, not configuration
.PHONY: firewall-skynet-running
firewall-skynet-running: firewall-install firewall-base-running | ssh-check
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

.PHONY: firewall-started
firewall-started: firewall-base-running

.PHONY: firewall-hardened
firewall-hardened: firewall-started firewall-skynet-running firewall-ipv6-forwarding
	@echo "🛡️ Firewall hardened and actively blocking threats"

.PHONY: firewall
firewall: firewall-skynet-running

.PHONY: firewall-audit
firewall-audit: | ssh-check
	@echo "🔍 Router firewall audit"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		iptables  -S INPUT; \
		iptables  -S FORWARD; \
		ip6tables -S INPUT; \
		ip6tables -S FORWARD; \
		wg show \
	'

.PHONY: firewall-ipv6-forwarding
firewall-ipv6-forwarding: | ssh-check
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
