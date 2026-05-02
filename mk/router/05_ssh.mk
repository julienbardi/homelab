# mk/router/05_ssh.mk

# --- DEFAULTS & CONFIG ---
ROUTER_ID_FILE ?= .tmp/router-owner-group
ROUTER_ID_TTL  ?= 60

# ------------------------------------------------------------
# ROUTER SSH PREFLIGHT & PRIVILEGE GUARDS
# ------------------------------------------------------------

.PHONY: router-ssh-check
router-ssh-check: install-ssh-config
	@$(WITH_SECRETS) \
		command -v nc >/dev/null 2>&1 || { echo "❌ Missing dependency: nc"; exit 1; }; \
		nc -z -w 2 $$router_addr $$router_ssh_port >/dev/null 2>&1 || { \
			echo "❌ Router unreachable on $$router_addr:$$router_ssh_port"; \
			exit 1; \
		}; \
		ssh -q -o BatchMode=yes -o ConnectTimeout=5 $$router_user@$$router_addr true >/dev/null 2>&1 || { \
			echo "❌ SSH reachable but authentication failed for $$router_user"; \
			exit 1; \
		}

.PHONY: router-require-run-as-root
router-require-run-as-root: | router-ssh-check
	@$(WITH_SECRETS) \
		if [ "$$ROUTER_BOOTSTRAP" = "1" ]; then exit 0; fi; \
		ssh $$router_user@$$router_addr 'test -x /jffs/scripts/run-as-root' || { \
			echo "❌ run-as-root missing"; \
			echo "ℹ️  Router helpers not installed"; \
			echo "📍 Recovery: make router-bootstrap"; \
			exit 1; \
		}

.PHONY: get-router-root-identity
get-router-root-identity: router-require-run-as-root
	@mkdir -p $(dir $(ROUTER_ID_FILE))
	@$(WITH_SECRETS) \
		echo "🔍 Checking identity for $$router_user on $$router_addr..."; \
		if [ -f $(ROUTER_ID_FILE) ] && [ "$(FORCE)" != "1" ]; then \
			now=$$(date +%s); \
			mtime=$$(stat -c %Y $(ROUTER_ID_FILE) 2>/dev/null || stat -f %m $(ROUTER_ID_FILE) 2>/dev/null || echo 0); \
			age=$$((now - mtime)); \
			if [ $$age -lt $(ROUTER_ID_TTL) ]; then exit 0; fi; \
		fi; \
		LOCKDIR=$(dir $(ROUTER_ID_FILE))/lock; \
		mkdir $$LOCKDIR 2>/dev/null || exit 0; \
		ssh $$router_user@$$router_addr 'awk -F: -v U="'"$$router_user"'" '\''FILENAME=="/etc/group"{g[$$3]=$$1; next} FILENAME=="/etc/passwd"{ if($$1==U){printf "%s:%s:%s:%s\n",$$3,$$4,$$1,(g[$$4]||""); found=1; exit}} END{if(!found) print "MISSING"}'\'' /etc/group /etc/passwd' > $(ROUTER_ID_FILE).tmp; \
		mv -f $(ROUTER_ID_FILE).tmp $(ROUTER_ID_FILE); \
		rmdir $$LOCKDIR; \
		R_ID=$$(cat $(ROUTER_ID_FILE)); \
		if [ "$$R_ID" = "MISSING" ]; then echo "❌ User $$router_user not found"; rm -f $(ROUTER_ID_FILE); exit 2; fi; \
		echo "✅ Resolved: $$R_ID"