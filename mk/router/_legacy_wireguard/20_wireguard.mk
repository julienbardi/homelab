# mk/router/20_wireguard.mk
# ------------------------------------------------------------
# ROUTER WIREGUARD (transport + policy)
# ------------------------------------------------------------

.PHONY: router-wg-transport-deploy
router-wg-transport-deploy:
	@$(call PUSH_ROUTER_SCRIPT, $(ROUTER_SCRIPTS_SRC_DIR)/wg-transport-apply, $(ROUTER_SCRIPTS)/wg-transport-apply)

.PHONY: router-wg-transport-apply
router-wg-transport-apply:
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '$(ROUTER_SCRIPTS)/wg-transport-apply'

.PHONY: router-wg-transport
router-wg-transport: router-wg-transport-deploy router-wg-transport-apply

.PHONY: router-wg-policy-deploy
router-wg-policy-deploy:
	@$(call PUSH_ROUTER_SCRIPT, $(ROUTER_SCRIPTS_SRC_DIR)/wg-policy-apply, $(ROUTER_SCRIPTS)/wg-policy-apply)

.PHONY: router-wg-plan-deploy
router-wg-plan-deploy:
	@$(INSTALL_PATH)/install_file_if_changed_v2.sh -q \
		"" "" "$(ROUTER_WG_PLAN_SRC)" \
		"$(ROUTER_HOST)" "$(ROUTER_SSH_PORT)" "$(ROUTER_SCRIPTS)/wireguard/plan.tsv" \
		"$(ROUTER_SCRIPTS_OWNER)" \
		"$(ROUTER_SCRIPTS_GROUP)" \
		"$(ROUTER_WG_PLAN_MODE)" \
		"$(ROUTER_USER)" \
	|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]

.PHONY: router-wg-policy-apply
router-wg-policy-apply:
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '$(ROUTER_SCRIPTS)/wg-policy-apply'

.PHONY: router-wg-policy
router-wg-policy: \
	router-wg-plan-deploy \
	router-wg-policy-deploy \
	router-wg-policy-apply

.PHONY: router-wg-converge
router-wg-converge: router-wg-transport router-wg-policy
	@echo "🔐 WireGuard transport + policy converged"

.PHONY: router-wg-audit
router-wg-audit: | router-ssh-check
	@echo "🔍 WireGuard security audit"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		set -e; \
		echo "→ IPv4 policy chain:"; \
		iptables -S WGSF || { echo "❌ WGSF missing"; exit 1; }; \
		echo; \
		echo "→ IPv6 policy chain:"; \
		ip6tables -S WGSF6 || { echo "❌ WGSF6 missing"; exit 1; }; \
		echo; \
		echo "→ FORWARD hooks:"; \
		iptables  -S FORWARD | grep -E "wg\\+.*WGSF" || \
			{ echo "❌ missing IPv4 wg → WGSF hook"; exit 1; }; \
		ip6tables -S FORWARD | grep -E "wg\\+.*WGSF6" || \
			{ echo "❌ missing IPv6 wg → WGSF6 hook"; exit 1; }; \
		echo; \
		echo "✅ WireGuard policy hooks verified"; \
		wg show \
	'

.PHONY: router-wg-reset
router-wg-reset: | router-ssh-check
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		iptables  -F WGSF  2>/dev/null || true; \
		ip6tables -F WGSF6 2>/dev/null || true; \
		echo "⚠️  WireGuard policy chains flushed (transport untouched)" \
	'
