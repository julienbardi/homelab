# mk/56_router-certs.mk — Router certificate deployment (namespaced)
# ------------------------------------------------------------
# CERTIFICATE DEPLOYMENT AND VALIDATION
# ------------------------------------------------------------

ifndef CERTS_DEPLOY
$(error CERTS_DEPLOY is not defined. This module requires CERTS_DEPLOY to be set by the including Makefile to an executable command that deploys certificates on the router.)
endif

define deploy_with_status
	@$(run_as_root) $(CERTS_DEPLOY) deploy $(1)
	@if [ "$(1)" = "caddy" ]; then \
		$(run_as_root) /jffs/scripts/caddy-reload.sh; \
	fi
endef

define validate_with_status
	@$(run_as_root) $(CERTS_DEPLOY) validate $(1)
endef

# ------------------------------------------------------------
# Router‑side namespaced targets
# ------------------------------------------------------------

.PHONY: router-certs-prereqs-ssh
router-certs-prereqs-ssh:
	@ssh -o BatchMode=yes -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) true 2>/dev/null || { \
		echo "❌ SSH key authentication to router failed"; \
		exit 1; \
	}

.PHONY: router-certs-deploy-script
router-certs-deploy-script:
	$(call deploy_if_changed,$(SRC_SCRIPTS)/certs-deploy.sh,/jffs/scripts/certs-deploy.sh)

.PHONY: router-certs-prepare
router-certs-prepare: router-certs-deploy-script router-require-run-as-root
	@$(run_as_root) $(CERTS_DEPLOY) prepare

.PHONY: router-certs-deploy
router-certs-deploy: router-certs-prereqs-ssh router-certs-prepare
	$(call deploy_with_status,router)

.PHONY: router-certs-validate
router-certs-validate: router-certs-deploy
	$(call validate_with_status,router)

.PHONY: router-certs-validate-caddy
router-certs-validate-caddy: router-certs-deploy
	$(call validate_with_status,caddy)
