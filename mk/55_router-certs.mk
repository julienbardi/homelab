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
	@newsum=$$(HOME=$(ACTUAL_HOME) $(run_as_root) sha256sum "$(SSL_CANONICAL_DIR)/fullchain_ecc.pem" "$(SSL_CANONICAL_DIR)/privkey_ecc.pem" | sha256sum | cut -d' ' -f1); \
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
# Internal: Generate router apply script safely
# ------------------------------------------------------------
/tmp/router-apply-local.sh:
	@echo "🛠️  Generating router apply script"
	@printf '%s\n' \
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
		> /tmp/router-apply-local.sh
	@chmod 0755 /tmp/router-apply-local.sh
	@echo "📄  Router apply script deployed"

# ------------------------------------------------------------
# Internal: Deploy certs + apply script + execute apply (Zero-disk memory pipe)
# ------------------------------------------------------------
/tmp/router-deploy.stamp: /tmp/router-apply-local.sh
	@set -e; \
	echo "📁  Uploading router certs + apply script + executing apply (streaming)"; \
	{ \
		echo "===FULLCHAIN==="; \
		HOME=$(ACTUAL_HOME) $(run_as_root) cat "$(SSL_CANONICAL_DIR)/fullchain_ecc.pem"; \
		echo "===PRIVKEY==="; \
		HOME=$(ACTUAL_HOME) $(run_as_root) cat "$(SSL_CANONICAL_DIR)/privkey_ecc.pem"; \
		echo "===APPLY==="; \
		cat /tmp/router-apply-local.sh; \
	} | ssh -o BatchMode=no -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) ' \
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
	' >/dev/null 2>&1; \
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

# mk/56_router-certs.mk — Router certificate deployment (namespaced)
# ------------------------------------------------------------
# CERTIFICATE DEPLOYMENT AND VALIDATION
# ------------------------------------------------------------

ifndef CERTS_DEPLOY
$(error CERTS_DEPLOY is not defined. This module requires CERTS_DEPLOY to be set by the including Makefile to an executable command that deploys certificates on the router.)
endif

define deploy_with_status
	@ROUTER_ADDR="$(ROUTER_ADDR)" \
	ROUTER_SSH_PORT="$(ROUTER_SSH_PORT)" \
	SSH_USER_ROUTER="$(SSH_USER_ROUTER)" \
	SSH_OPTS="$(SSH_OPTS) -F $(HOME)/.ssh/config -i $(HOME)/.ssh/id_ed25519" \
	$(run_as_root) $(CERTS_DEPLOY) deploy $(1)
	@if [ "$(1)" = "caddy" ]; then \
		$(run_as_root) /jffs/scripts/caddy-reload.sh; \
	fi
endef

define validate_with_status
	@$(run_as_root) $(CERTS_DEPLOY) validate $(1)
endef

# ------------------------------------------------------------
# Router-side namespaced targets
# ------------------------------------------------------------

.PHONY: router-certs-prereqs-ssh
router-certs-prereqs-ssh:
	@$(call WITH_SECRETS, \
		ssh $(SSH_OPTS) -o BatchMode=yes -p "$(ROUTER_SSH_PORT)" "$(SSH_USER_ROUTER)@$(ROUTER_ADDR)" true \
	) 2>/dev/null || { \
		echo "❌ SSH key authentication to router failed"; \
		exit 1; \
	}

.PHONY: router-certs-prepare
router-certs-prepare: install-all router-certs-deploy-script router-require-run-as-root
	@ROUTER_ADDR="$(ROUTER_ADDR)" \
	ROUTER_SSH_PORT="$(ROUTER_SSH_PORT)" \
	SSH_USER_ROUTER="$(SSH_USER_ROUTER)" \
	SSH_OPTS="$(SSH_OPTS) -F $(HOME)/.ssh/config -i $(HOME)/.ssh/id_ed25519" \
	$(run_as_root) $(CERTS_DEPLOY) prepare

.PHONY: router-certs-deploy
router-certs-deploy: router-bootstrap-run-as-root install-all router-certs-prereqs-ssh router-certs-prepare
	$(call deploy_with_status,router)

.PHONY: install-all router-certs-validate
router-certs-validate: router-certs-deploy
	$(call validate_with_status,router)

.PHONY: router-certs-validate-caddy
router-certs-validate-caddy: install-all router-certs-deploy
	$(call validate_with_status,caddy)

.PHONY: router-certs-deploy-script
router-certs-deploy-script:
	@$(call WITH_SECRETS, \
		$(INSTALL_FILE_IF_CHANGED) "" "" "$(SRC_SCRIPTS)/certs-deploy.sh" \
			"$(ROUTER_ADDR)" "$(ROUTER_SSH_PORT)" "/jffs/scripts/certs-deploy.sh" \
			$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE) \
	)

.PHONY: router-certs-status
router-certs-status: router-bootstrap router-certs-prepare
	@$(call WITH_SECRETS, sh -c '\
		ROUTER_ADDR="$(ROUTER_ADDR)" \
		ROUTER_SSH_PORT="$(ROUTER_SSH_PORT)" \
		SSH_USER_ROUTER="$(SSH_USER_ROUTER)" \
		SSH_OPTS="$(SSH_OPTS)" \
		$(CERTS_DEPLOY) status router \
	')

