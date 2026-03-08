# mk/router/ssh.mk
# ------------------------------------------------------------
# ROUTER SSH PREFLIGHT & PRIVILEGE GUARDS
# ------------------------------------------------------------
#
# Responsibilities:
#   - Router reachability checks
#   - SSH connectivity validation
#   - Presence verification of privileged helpers
#
# Non-responsibilities:
#   - Deployment of router artifacts
#   - Firewall or service configuration
#   - State mutation on the router
#
# Contracts:
#   - Read-only checks only
#   - Safe under 'make -j'
#   - MUST NOT mutate router state
# ------------------------------------------------------------

.PHONY: ssh-check
ssh-check:
	@command -v nc >/dev/null 2>&1 || \
	( \
		echo "❌ Missing dependency: nc (netcat)"; \
		echo "Install it with: sudo apt install netcat-openbsd"; \
		exit 1; \
	)
	@nc -z -w 2 $(ROUTER_ADDR) $(ROUTER_SSH_PORT) >/dev/null 2>&1 || \
	( \
		echo "❌ Router unreachable on $(ROUTER_ADDR):$(ROUTER_SSH_PORT)"; \
		echo "   (host down, port filtered, or network issue)"; \
		exit 1; \
	)
	@ssh -p $(ROUTER_SSH_PORT) -o BatchMode=yes -o ConnectTimeout=5 \
		$(ROUTER_HOST) true >/dev/null 2>&1 || \
	( \
		echo "❌ SSH reachable but authentication failed"; \
		exit 1; \
	)

.PHONY: require-run-as-root
require-run-as-root: | ssh-check
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		test -x "$(RUN_AS_ROOT)" || \
		( \
			echo "❌ run-as-root missing"; \
			echo "ℹ️  Router helpers not installed (likely after reset)"; \
			echo "➡️  Recovery: make bootstrap"; \
			exit 1; \
		) \
	'
