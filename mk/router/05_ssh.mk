# mk/router/05_ssh.mk

# --- DEFAULTS & CONFIG ---
ROUTER_ID_FILE ?= .tmp/router-owner-group
ROUTER_ID_TTL  ?= 60

# ROUTER_BOOTSTRAP is an orchestration flag:
# - empty  => normal operations
# - "1"    => running under router-bootstrap
export ROUTER_BOOTSTRAP ?=

# ------------------------------------------------------------
# ROUTER SSH PREFLIGHT & PRIVILEGE GUARDS
# ------------------------------------------------------------

.PHONY: router-ssh-check
router-ssh-check: install-ssh-config
	@if [ "$(VERBOSE)" -ge 1 ]; then \
		echo "🔍 Checking router SSH ($(SSH_USER_ROUTER)@$(ROUTER_ADDR):$(ROUTER_SSH_PORT))"; \
		echo "  • Checking TCP reachability"; \
	fi

	@{ \
		exec 3<>/dev/tcp/"$(ROUTER_ADDR)"/"$(ROUTER_SSH_PORT)" 2>/dev/null || { \
			echo "❌ Router unreachable on $(ROUTER_ADDR):$(ROUTER_SSH_PORT)"; \
			exit 1; \
		}; \
		exec 3>&-; \
	}

	@if [ "$(VERBOSE)" -ge 1 ]; then \
		echo "  • Checking SSH authentication"; \
	fi

	@ssh -q \
		-o BatchMode=yes \
		-o ConnectTimeout=5 \
		"$(SSH_HOST_ROUTER)" \
		true >/dev/null 2>&1 || { \
		echo "❌ SSH reachable but authentication failed for $(SSH_USER_ROUTER)"; \
		exit 1; \
	}

	@if [ "$(VERBOSE)" -ge 1 ]; then \
		echo "🟢 Router SSH OK — authenticated as $(SSH_USER_ROUTER)"; \
	fi


.PHONY: router-require-run-as-root
router-require-run-as-root: | router-ssh-check
	# Skip check during bootstrap
	@if [ "$(ROUTER_BOOTSTRAP)" = "1" ]; then exit 0; fi

	@echo "🔍 Checking router run-as-root helper"

	@ssh "$(SSH_HOST_ROUTER)" \
		'test -x /jffs/scripts/run-as-root' >/dev/null 2>&1 || { \
			echo "❌ run-as-root missing on router"; \
			echo "ℹ️  Router helpers not installed"; \
			echo " Recovery: make router-bootstrap"; \
			exit 1; \
		}

	@echo "🟢 run-as-root OK — helper installed and executable"

.PHONY: get-router-root-identity
get-router-root-identity: router-require-run-as-root
	@echo "🔍 Checking router identity for $(SSH_USER_ROUTER) on $(ROUTER_ADDR)"

	# Ensure cache directory exists
	@mkdir -p "$(dir $(ROUTER_ID_FILE))"

	# 1. TTL-based cache check
	@if [ -f "$(ROUTER_ID_FILE)" ] && [ "$(FORCE)" != "1" ]; then \
		now=$$(date +%s); \
		mtime=$$(stat -c %Y "$(ROUTER_ID_FILE)" 2>/dev/null || stat -f %m "$(ROUTER_ID_FILE)" 2>/dev/null || echo 0); \
		age=$$((now - mtime)); \
		if [ $$age -lt "$(ROUTER_ID_TTL)" ]; then \
			exit 0; \
		fi; \
	fi

	# 2. Lock to avoid races under -j
	@LOCKDIR="$(dir $(ROUTER_ID_FILE))/lock"; \
	mkdir "$$LOCKDIR" 2>/dev/null || exit 0

	# 3. Remote identity lookup (BusyBox-safe AWK)
	@ssh "$(SSH_HOST_ROUTER)" \
		'awk -F: -v U="$(SSH_USER_ROUTER)" '\'' \
			FILENAME=="/etc/group"  { g[$$3]=$$1; next } \
			FILENAME=="/etc/passwd" { if ($$1==U) { printf "%s:%s:%s:%s\n", $$3, $$4, $$1, (g[$$4]||""); found=1; exit } } \
			END { if (!found) print "MISSING" } \
		'\'' /etc/group /etc/passwd' \
		> "$(ROUTER_ID_FILE).tmp"

	# 4. Commit result + release lock
	@mv -f "$(ROUTER_ID_FILE).tmp" "$(ROUTER_ID_FILE)"
	@rmdir "$(dir $(ROUTER_ID_FILE))/lock"

	# 5. Validate result
	@R_ID="$$(cat "$(ROUTER_ID_FILE)")"; \
	if [ "$$R_ID" = "MISSING" ]; then \
		echo "❌ Router user $(SSH_USER_ROUTER) not found"; \
		rm -f "$(ROUTER_ID_FILE)"; \
		exit 2; \
	fi

	@echo "🟢 Router identity OK — $$R_ID"

# Path to the interactive known_hosts installer
KNOWN_HOSTS_SCRIPT := $(INSTALL_PATH)/verify_and_install_known_hosts.sh

# Allow skipping in CI or when explicitly requested
SKIP_KNOWN_HOSTS ?= 0

.PHONY: ensure-known-hosts
ensure-known-hosts: $(KNOWN_HOSTS_SCRIPT)
	@echo "🔐 Ensuring known_hosts entries..."
	@if [ "$(SKIP_KNOWN_HOSTS)" != "1" ]; then \
		timeout 1.5 bash "$(KNOWN_HOSTS_SCRIPT)" || true; \
	fi