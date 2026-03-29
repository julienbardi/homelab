# mk/router/05_ssh.mk
# ------------------------------------------------------------
# ROUTER SSH PREFLIGHT & PRIVILEGE GUARDS (namespaced)
# ------------------------------------------------------------
#
# Responsibilities:
#   - Router reachability checks
#   - SSH connectivity validation
#   - Presence verification of privileged helpers
#
# Contracts:
#   - Read-only checks only
#   - Safe under 'make -j'
#   - MUST NOT mutate router state
# ------------------------------------------------------------

.PHONY: router-ssh-check
router-ssh-check: install-ssh-config
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

.PHONY: router-require-run-as-root
router-require-run-as-root: | router-ssh-check
	@if [ "$$ROUTER_BOOTSTRAP" = "1" ]; then exit 0; fi
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		test -x /jffs/scripts/run-as-root || \
		( \
			echo "❌ run-as-root missing"; \
			echo "ℹ️  Router helpers not installed (likely after reset)"; \
			echo "➡️  Recovery: make router-bootstrap"; \
			exit 1; \
		) \
	'
