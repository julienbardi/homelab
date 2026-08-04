# ============================================================
# mk/55_router-certs.mk — Unified Router Certificate Deployment
# ============================================================
# CONTRACT:
# - SSH-based targets must NEVER run as root.
# - Deployment is delegated to CERTS_DEPLOY (single implementation).
# - Provides legacy targets: deploy-router, validate-router, router-logs.
# - Provides namespaced targets: router-certs-*.
# - No tmp scripts, no streaming hacks, no checksums.
# ============================================================

SENSITIVE_ROUTER_GOALS := \
	deploy-router \
	validate-router \
	router-logs \
	router-certs-deploy \
	router-certs-validate \
	router-certs-status \
	router-certs-validate-caddy

ifneq ($(filter $(SENSITIVE_ROUTER_GOALS),$(MAKECMDGOALS)),)
	ifeq ($(shell id -u),0)
		$(error ❌ Do not run $(filter $(SENSITIVE_ROUTER_GOALS),$(MAKECMDGOALS)) as root; run as an unprivileged user)
	endif
endif

ifndef CERTS_DEPLOY
$(error CERTS_DEPLOY is not defined. This module requires CERTS_DEPLOY to be set by mk/50_certs.mk)
endif

# ------------------------------------------------------------
# Shared helpers
# ------------------------------------------------------------
define router_deploy_with_status
	ROUTER_ADDR="$(ROUTER_ADDR)" \
	ROUTER_SSH_PORT="$(ROUTER_SSH_PORT)" \
	SSH_USER_ROUTER="$(SSH_USER_ROUTER)" \
	SSH_OPTS="$(SSH_OPTS) -F $(HOME)/.ssh/config -i $(HOME)/.ssh/id_ed25519" \
	$(run_as_root) $(CERTS_DEPLOY) deploy $(1)
endef

define router_validate_with_status
	@$(run_as_root) $(CERTS_DEPLOY) validate $(1)
endef

# ------------------------------------------------------------
# SSH prereqs
# ------------------------------------------------------------
.PHONY: router-certs-prereqs-ssh $(STAMP_SOPS)
router-certs-prereqs-ssh:
	@$(call WITH_SECRETS, \
		ssh "$(SSH_HOST_ROUTER)" true \
	) 2>/dev/null || { \
		echo "❌ SSH key authentication to router failed"; \
		exit 1; \
	}

# ------------------------------------------------------------
# Prepare router-side deploy tooling
# ------------------------------------------------------------
.PHONY: router-certs-deploy-script
router-certs-deploy-script: $(STAMP_SOPS)
	@$(call WITH_SECRETS, \
		$(INSTALL_FILE_IF_CHANGED) "" "" "$(SRC_SCRIPTS)/certs-deploy.sh" \
			"$(ROUTER_ADDR)" "$(ROUTER_SSH_PORT)" "/jffs/scripts/certs-deploy.sh" \
			$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE) \
	)

router-certs-prepare: install-all router-certs-deploy-script router-require-run-as-root $(STAMP_SOPS)
	@$(call WITH_SECRETS, \
		ROUTER_ADDR="$(ROUTER_ADDR)" \
		ROUTER_SSH_PORT="$(ROUTER_SSH_PORT)" \
		SSH_USER_ROUTER="$(SSH_USER_ROUTER)" \
		SSH_OPTS="$(SSH_OPTS) -F $(HOME)/.ssh/config -i $(HOME)/.ssh/id_ed25519" \
		$(run_as_root) $(CERTS_DEPLOY) prepare \
	)

# ------------------------------------------------------------
# Namespaced deploy + validate
# ------------------------------------------------------------
.PHONY: router-certs-deploy
router-certs-deploy: router-bootstrap-primitives install-all router-certs-prereqs-ssh router-certs-prepare $(STAMP_SOPS)
	$(call WITH_SECRETS, $(call router_deploy_with_status,router))

.PHONY: router-certs-validate
router-certs-validate: router-certs-deploy $(STAMP_SOPS)
	$(call WITH_SECRETS, $(call router_validate_with_status,router))

.PHONY: router-certs-validate-caddy
router-certs-validate-caddy: install-all router-certs-deploy $(STAMP_SOPS)
	$(call WITH_SECRETS, $(call router_validate_with_status,caddy))

.PHONY: router-certs-status
router-certs-status: router-bootstrap router-certs-prepare $(STAMP_SOPS)
	@$(call WITH_SECRETS, sh -c '\
		ROUTER_ADDR="$(ROUTER_ADDR)" \
		ROUTER_SSH_PORT="$(ROUTER_SSH_PORT)" \
		SSH_USER_ROUTER="$(SSH_USER_ROUTER)" \
		SSH_OPTS="$(SSH_OPTS)" \
		$(CERTS_DEPLOY) status router \
	')

# ------------------------------------------------------------
# Legacy compatibility targets (required by mk/50_certs.mk)
# ------------------------------------------------------------
.PHONY: deploy-router
deploy-router: router-certs-deploy
	@echo "🔄 Router certificate deploy completed (CERTS_DEPLOY)"

.PHONY: validate-router
validate-router: router-certs-validate
	@echo "✅ Router certificate validation OK (CERTS_DEPLOY)"

.PHONY: router-logs
router-logs:
	@echo "Tailing router certificate logs"
	@ssh "$(SSH_HOST_ROUTER)" "logread -f | grep -E 'router-cert-apply'"
