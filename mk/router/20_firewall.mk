# mk/router/20_firewall.mk
# ------------------------------------------------------------
# ROUTER FIREWALL & DNSMASQ CONVERGENCE (namespaced)
# ------------------------------------------------------------

.NOTPARALLEL: \
	router-dnsmasq-cache \
	router-firewall-install

# ------------------------------------------------------------
# dnsmasq cache configuration
# ------------------------------------------------------------

DNSMASQ_CONF_ADD   := $(ROUTER_DNSMASQ_CONF_ADD)
DNSMASQ_CACHE_LINE := $(ROUTER_DNSMASQ_CACHE_LINE)

$(if $(strip $(DNSMASQ_CONF_ADD)),,$(error DNSMASQ_CONF_ADD is empty))
$(if $(strip $(DNSMASQ_CACHE_LINE)),,$(error DNSMASQ_CACHE_LINE is empty))

.PHONY: router-dnsmasq-cache
router-dnsmasq-cache: | router-ssh-check
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		set -e; \
		mkdir -p /jffs/configs; \
		touch "$(DNSMASQ_CONF_ADD)"; \
		if grep -qx "$(DNSMASQ_CACHE_LINE)" "$(DNSMASQ_CONF_ADD)"; then \
			echo "dnsmasq cache OK"; \
		else \
			tmp="$(DNSMASQ_CONF_ADD).tmp.$$"; \
			printf "%s\n" "$(DNSMASQ_CACHE_LINE)" > "$$tmp"; \
			mv -f "$$tmp" "$(DNSMASQ_CONF_ADD)"; \
			service restart_dnsmasq; \
		fi \
	'

# ------------------------------------------------------------
# Firewall script deployment
# ------------------------------------------------------------

.PHONY: router-firewall-install
router-firewall-install: | router-ssh-check router-require-run-as-root
	@$(INSTALL_FILE_IF_CHANGED) \
	"" "" $(SRC_SCRIPTS)/firewall-start \
	$(ROUTER_HOST) $(ROUTER_SSH_PORT) /jffs/scripts/firewall-start \
	root root 0755


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
