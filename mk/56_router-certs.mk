# mk/56_router-certs.mk — Router certificate deployment (namespaced)
# ------------------------------------------------------------
# CERTIFICATE DEPLOYMENT AND VALIDATION
# ------------------------------------------------------------

ifndef CERTS_DEPLOY
$(error CERTS_DEPLOY is not defined. This module requires CERTS_DEPLOY to be set by the including Makefile to an executable command that deploys certificates on the router.)
endif

define deploy_with_status
	@ROUTER_ADDR="$$router_addr" \
	ROUTER_SSH_PORT="$$router_ssh_port" \
	ROUTER_USER="$$router_user" \
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
		ssh $(SSH_OPTS) -o BatchMode=yes -p "$$router_ssh_port" "$$router_user@$$router_addr" true \
	) 2>/dev/null || { \
		echo "❌ SSH key authentication to router failed"; \
		exit 1; \
	}

.PHONY: router-certs-prepare
router-certs-prepare: install-all router-certs-deploy-script router-require-run-as-root
	@ROUTER_ADDR="$$router_addr" \
	ROUTER_SSH_PORT="$$router_ssh_port" \
	ROUTER_USER="$$router_user" \
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
			"$$router_addr" "$$router_ssh_port" "/jffs/scripts/certs-deploy.sh" \
			$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE) \
	)

.PHONY: router-certs-status
router-certs-status: router-bootstrap router-certs-prepare
	@$(WITH_SECRETS) \
		ROUTER_ADDR="$(router_addr)" \
		ROUTER_SSH_PORT="$(router_ssh_port)" \
		ROUTER_USER="$(router_user)" \
		SSH_OPTS="$(SSH_OPTS)" \
		$(CERTS_DEPLOY) status router
