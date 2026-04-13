# ============================================================
# mk/55_router_certs.mk — Router certificate deployment
# ============================================================
# SSH-based targets that should NEVER be run as root to protect the user's SSH environment
SENSITIVE_ROUTER_GOALS := deploy-router router-all router-all-full

ifneq ($(filter $(SENSITIVE_ROUTER_GOALS),$(MAKECMDGOALS)),)
	ifeq ($(shell id -u),0)
		$(error ❌ Do not run $(filter $(SENSITIVE_ROUTER_GOALS),$(MAKECMDGOALS)) as root; run as an unprivileged user)
	endif
endif

ROUTER_CERT_CHECKSUM := /tmp/router-cert-checksum.txt

# Better checksum logic to prevent unnecessary re-runs
$(ROUTER_CERT_CHECKSUM):
	@mkdir -p /tmp
	@newsum=$$(HOME=/home/julie $(run_as_root) sha256sum "$(SSL_CANONICAL_DIR)/fullchain_ecc.pem" "$(SSL_CANONICAL_DIR)/privkey_ecc.pem" | sha256sum | cut -d' ' -f1); \
	oldsum=$$(cat $@ 2>/dev/null || echo ""); \
	if [ "$$newsum" != "$$oldsum" ]; then \
		echo "$$newsum" > $@; \
		echo "🔐 Router cert checksum updated"; \
		rm -f /tmp/router-deploy.stamp; \
	fi

# ------------------------------------------------------------
# Internal: ensure SSH key auth works for router
# ------------------------------------------------------------
.PHONY: prereqs-router-ssh
prereqs-router-ssh:
	@ssh -o BatchMode=yes -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) true 2>/dev/null || { \
		echo "❌ SSH key authentication to router failed (BatchMode refused)"; \
		echo "👉 Your key *is probably already installed*, but the router is rejecting non-interactive key auth."; \
		echo "👉 Fix this in the router UI: Administration -> System -> SSH Daemon:"; \
		echo "       • Enable SSH"; \
		echo "       • SSH Port: $(ROUTER_SSH_PORT)"; \
		echo "       • Allow SSH key authentication: ON"; \
		echo "       • Allow SSH key authentication for LAN: ON"; \
		echo "       • Ensure your key is in julie’s authorized_keys"; \
		echo "👉 If needed, reinstall key: ssh-copy-id -p $(ROUTER_SSH_PORT) $(ROUTER_HOST)"; \
		exit 1; \
	}

# ------------------------------------------------------------
# Internal: Generate and deploy router apply script
# ------------------------------------------------------------
/tmp/router-apply-local.sh:
	@echo "🛠️  Generating router apply script"
	@set -e; \
	tmp=$$(mktemp /tmp/router-apply-XXXXXX.sh); \
	printf '%s\n' \
		'#!/bin/sh' \
		'set -eu' \
		'' \
		'SRC_CHAIN="/jffs/ssl/fullchain.pem"' \
		'SRC_KEY="/jffs/ssl/privkey.pem"' \
		'' \
		'DST_CERT="/tmp/etc/cert.pem"' \
		'DST_KEY="/tmp/etc/key.pem"' \
		'' \
		'log() { logger -t "router-cert-apply" "$$*"; echo "$$*"; }' \
		'' \
		'if [ ! -f "$$SRC_CHAIN" ] || [ ! -f "$$SRC_KEY" ]; then' \
		'   log "❌ source cert/key missing in /jffs/ssl"' \
		'   exit 1' \
		'fi' \
		'' \
		'cp "$$SRC_CHAIN" "$$DST_CERT"' \
		'cp "$$SRC_KEY" "$$DST_KEY"' \
		'' \
		'chmod 0644 "$$DST_CERT"' \
		'chmod 0600 "$$DST_KEY"' \
		'' \
		'log "🔐 installed ECC cert/key to $$DST_CERT"' \
		'' \
		'service restart_httpd 2>/dev/null || log "⚠️ restart_httpd failed (non-fatal)"' \
		'service restart_httpds 2>/dev/null || log "⚠️ restart_httpds failed (non-fatal)"' \
		'' \
		'log "✅ router UI cert apply complete"' \
		> "$$tmp"; \
	cp "$$tmp" /tmp/router-apply-local.sh; \
	rm -f "$$tmp"
	@echo "📄  Router apply script deployed"

# ------------------------------------------------------------
# Internal: Deploy certs + apply script + execute apply (BusyBox-safe single SSH session)
# ------------------------------------------------------------
/tmp/router-deploy.stamp: /tmp/router-apply-local.sh
	@set -e; \
	echo "📁  Uploading router certs + apply script + executing apply"; \
	tmp=/tmp/router-bundle-$$.tmp; \
	{ \
		echo "===FULLCHAIN==="; \
		HOME=/home/julie $(run_as_root) cat "$(SSL_CANONICAL_DIR)/fullchain_ecc.pem"; \
		echo "===PRIVKEY==="; \
		HOME=/home/julie $(run_as_root) cat "$(SSL_CANONICAL_DIR)/privkey_ecc.pem"; \
		echo "===APPLY==="; \
		cat /tmp/router-apply-local.sh; \
	} > "$$tmp"; \
	\
	ssh -o BatchMode=no -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) ' \
		mkdir -p /jffs/ssl && chmod 700 /jffs/ssl; \
		: > /jffs/scripts/apply-router-cert.sh; \
		mode=none; \
		while IFS='' read -r line; do \
			case "$$line" in \
				"===FULLCHAIN===") mode="fullchain"; continue ;; \
				"===PRIVKEY===")   mode="privkey";   continue ;; \
				"===APPLY===")     mode="apply";     continue ;; \
			esac; \
			case "$$mode" in \
				fullchain) echo "$$line" >> /jffs/ssl/fullchain.pem ;; \
				privkey)   echo "$$line" >> /jffs/ssl/privkey.pem ;; \
				apply)     echo "$$line" >> /jffs/scripts/apply-router-cert.sh ;; \
			esac; \
		done; \
		chmod 0644 /jffs/ssl/fullchain.pem; \
		chmod 0600 /jffs/ssl/privkey.pem; \
		chmod 0755 /jffs/scripts/apply-router-cert.sh; \
		/jffs/scripts/apply-router-cert.sh \
	' < "$$tmp" >/dev/null 2>&1; \
	rm -f "$$tmp"; \
	echo "ok" > /tmp/router-deploy.stamp; \
	echo "✨  Router certs uploaded + applied"

# ------------------------------------------------------------
# Public: deploy-router
# ------------------------------------------------------------
deploy-router: $(ROUTER_CERT_CHECKSUM) /tmp/router-deploy.stamp
	@echo "🔄 Nothing to deploy — router certs unchanged"

# ------------------------------------------------------------
# Public: validate-router
# ------------------------------------------------------------
validate-router:
	@echo "Validating router certificate"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '\
		if [ ! -f /tmp/etc/cert.pem ]; then echo "❌ cert.pem missing"; exit 1; fi; \
		if [ ! -f /tmp/etc/key.pem ]; then echo "❌ key.pem missing"; exit 1; fi; \
		echo "🔍 Router cert/key present"; \
	'
	@echo "✅ Router certificate validation OK"

# ------------------------------------------------------------
# Public: router-logs (live tail of router cert apply logs)
# ------------------------------------------------------------
router-logs:
	@echo "Tailing router certificate logs"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) "logread -f | grep -E 'router-cert-apply'"

.PHONY: \
deploy-router \
validate-router \
router-logs