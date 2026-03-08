# mk/certs.mk
# ------------------------------------------------------------
# CERTIFICATE DEPLOYMENT AND VALIDATION
# ------------------------------------------------------------
#
# Purpose:
#   Consume, deploy, and validate certificates produced externally.
#
# Responsibilities:
#   - Deploy certificates to router services
#   - Reload dependent services
#   - Validate certificate presence and expiry
#
# Non-responsibilities:
#   - Certificate authority operations
#   - Certificate creation or rotation
#   - ACME or renewal logic
#
# Authority:
#   - Certificates are produced externally (e.g. NAS)
#   - This module makes no assumptions about the issuer
#
# Safety:
#   - Missing or invalid certificates MUST fail loudly
#
# Contracts:
#   - MUST NOT assume presence of ACME tooling
#   - MUST NOT invoke $(MAKE)
#
# External requirements:
#   - CERTS_DEPLOY: executable certificate deployment command
#     (defined in mk/config.mk)
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

.PHONY: certs-deploy
certs-deploy: require-run-as-root certs-prepare
	@$(run_as_root) test -x $(CERTS_DEPLOY)
	@$(run_as_root) $(CERTS_DEPLOY)

.PHONY: certs-ensure
certs-ensure: certs-deploy ## Ensure certificates are present and deployed

.PHONY: certs-status
certs-status:
	@$(run_as_root) ls -l /jffs/ssl || true

.PHONY: certs-expiry
certs-expiry:
	@$(run_as_root) openssl x509 -in /etc/ssl/certs/homelab_bardi_CA.pem -noout -enddate

.PHONY: deploy-router
deploy-router: router-prepare
	$(call deploy_with_status,router)

.PHONY: validate-router
validate-router: certs-ensure
	$(call validate_with_status,router)

.PHONY: validate-caddy
validate-caddy: certs-ensure
	$(call validate_with_status,caddy)

.PHONY: deploy-certs-deploy
deploy-certs-deploy:
	$(call deploy_if_changed,$(SRC_SCRIPTS)/certs-deploy.sh,/jffs/scripts/certs-deploy.sh)

.PHONY: certs-prepare
certs-prepare: deploy-certs-deploy require-run-as-root
	@$(run_as_root) $(CERTS_DEPLOY) prepare
