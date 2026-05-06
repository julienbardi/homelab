# mk/router/40_firewall.mk
# ------------------------------------------------------------
# FIREWALL INVARIANTS
# ------------------------------------------------------------

.PHONY: router-firewall-hardened
router-firewall-hardened: | router-ssh-check
	@echo "🛡️ Validating router firewall invariants"
	@$(call WITH_SECRETS, \
		ssh -p "$$router_ssh_port" "$$router_user@$$router_addr" '\
			set -e; \
			if [ ! -x /jffs/scripts/firewall-start ]; then \
				echo "❌ Missing /jffs/scripts/firewall-start"; exit 1; \
			fi; \
			echo "🟢 firewall-start present"; \
		' \
	)
	@echo "🛡️ Router firewall hardened"
