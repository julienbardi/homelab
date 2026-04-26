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
	@command -v nc >/dev/null 2>&1 || ( echo "❌ Missing dependency: nc (netcat)"; echo "Install it with: sudo apt install netcat-openbsd"; exit 1; )
	@nc -z -w 2 $(ROUTER_ADDR) $(ROUTER_SSH_PORT) >/dev/null 2>&1 || ( echo "❌ Router unreachable on $(ROUTER_ADDR):$(ROUTER_SSH_PORT)"; echo "   (host down, port filtered, or network issue)"; exit 1; )
	@$(ROUTER_SSH) -o BatchMode=yes -o ConnectTimeout=5 true >/dev/null 2>&1 || ( echo "❌ SSH reachable but authentication failed"; exit 1; )

.PHONY: router-require-run-as-root
router-require-run-as-root: | router-ssh-check
	@if [ "$$ROUTER_BOOTSTRAP" = "1" ]; then exit 0; fi
	@$(ROUTER_SSH) '\
		test -x /jffs/scripts/run-as-root || \
		( \
			echo "❌ run-as-root missing"; \
			echo "ℹ️  Router helpers not installed (likely after reset)"; \
			echo "📍  Recovery: make router-bootstrap"; \
			exit 1; \
		) \
	'

# safe defaults
ROUTER_ID_FILE ?= .tmp/router-owner-group
ROUTER_ID_TTL ?= 60

.PHONY: get-router-root-identity
get-router-root-identity: router-require-run-as-root
	@mkdir -p $(dir $(ROUTER_ID_FILE))
	@echo "🔍 get-router-root-identity: checking overrides and cache..."
	@if [ -n "$(ROUTER_UID)" ] && [ -n "$(ROUTER_GID)" ] && [ -n "$(ROUTER_USER_NAME)" ] && [ -n "$(ROUTER_GROUP_NAME)" ] && [ "$(FORCE)" != "1" ]; then printf '%s\n' "$(ROUTER_UID):$(ROUTER_GID):$(ROUTER_USER_NAME):$(ROUTER_GROUP_NAME)" > $(ROUTER_ID_FILE).tmp && mv -f $(ROUTER_ID_FILE).tmp $(ROUTER_ID_FILE) && exit 0; fi
	@if [ -f $(ROUTER_ID_FILE) ] && [ "$(FORCE)" != "1" ]; then now=$$(date +%s); mtime=$$(stat -c %Y $(ROUTER_ID_FILE) 2>/dev/null || stat -f %m $(ROUTER_ID_FILE) 2>/dev/null || echo 0); age=$$((now - mtime)); if [ $$age -lt $(ROUTER_ID_TTL) ]; then echo "Using cached $(ROUTER_ID_FILE) (age=$$age s < $(ROUTER_ID_TTL) s)"; exit 0; else echo "♻️ Cache stale (age=$$age s >= $(ROUTER_ID_TTL) s), re-resolving"; fi; fi
	@LOCKDIR=$(dir $(ROUTER_ID_FILE))/router-owner-group.lock; for i in 1 2 3 4 5; do mkdir $$LOCKDIR 2>/dev/null && break || sleep 0.05; done; if [ -d "$$LOCKDIR" ]; then echo "🔎 Resolving remote UID:GID:USER:GROUP for '$(ROUTER_USER)' on $(ROUTER_ADDR)..."; $(ROUTER_SSH) 'awk -F: -v U="$(ROUTER_USER)" '\''FILENAME=="/etc/group"{g[$$3]=$$1; next} FILENAME=="/etc/passwd"{ if($$1==U){printf "%s:%s:%s:%s\n",$$3,$$4,$$1,(g[$$4]||""); found=1; exit}} END{if(!found) print "MISSING"}'\'' /etc/group /etc/passwd' > $(ROUTER_ID_FILE).tmp.$$ 2>/dev/null || true; mv -f $(ROUTER_ID_FILE).tmp.$$ $(ROUTER_ID_FILE); rmdir $$LOCKDIR; else sleep 0.1; fi
	@if [ "$$(cat $(ROUTER_ID_FILE) 2>/dev/null || echo)" = "MISSING" ]; then echo "❌ User '$(ROUTER_USER)' not found on router $(ROUTER_ADDR)."; rm -f $(ROUTER_ID_FILE); exit 2; fi
	@R_UNAME=$$(printf "%s" "$$(cat $(ROUTER_ID_FILE))" | cut -d: -f3); if [ "$$R_UNAME" != "$(ROUTER_USER)" ]; then echo "❌ Resolved username '$$R_UNAME' does not match requested '$(ROUTER_USER)'."; rm -f $(ROUTER_ID_FILE); exit 3; fi
	@echo "✅ Resolved: $$(cat $(ROUTER_ID_FILE))"
