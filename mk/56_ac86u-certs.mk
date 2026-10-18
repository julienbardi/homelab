# VERSION: 1
# ============================================================
# mk/56_ac86u-certs.mk — RT-AC86U Certificate Deployment
# ============================================================
# CONTRACT:
# - SSH-based targets must NEVER run as root.
# - Deployment is delegated to CERTS_DEPLOY.
# - AC86U is managed independently from the primary router.
# - Uses canonical ECC certificate lineage.
# - Provides legacy targets:
#       deploy-ac86u
#       validate-ac86u
#       ac86u-logs
# - No temporary scripts.
# - No duplicated certificate generation logic.
# ============================================================

SENSITIVE_AC86U_GOALS := \
    deploy-ac86u \
    validate-ac86u \
    ac86u-logs \
    ac86u-certs-deploy \
    ac86u-certs-validate \
    ac86u-certs-status

ifneq ($(filter $(SENSITIVE_AC86U_GOALS),$(MAKECMDGOALS)),)
    ifeq ($(shell id -u),0)
        $(error ❌ Do not run $(filter $(SENSITIVE_AC86U_GOALS),$(MAKECMDGOALS)) as root; run as an unprivileged user)
    endif
endif

ifndef CERTS_DEPLOY
$(error CERTS_DEPLOY is not defined. This module requires CERTS_DEPLOY to be set by mk/50_certs.mk)
endif

# ------------------------------------------------------------
# AC86U identity
# ------------------------------------------------------------

define ac86u_validate_with_status
    $(run_as_root) env \
        SSL_CANONICAL_DIR="$(SSL_CANONICAL_DIR)" \
        DOMAIN="$(DOMAIN)" \
        ROUTER_ADDR="$(LAN_AC86U)" \
        ROUTER_SSH_PORT="$(SSH_PORT_AC86U)" \
        SSH_USER_ROUTER="$(SSH_USER_AC86U)" \
        $(CERTS_DEPLOY) validate router
endef

# ------------------------------------------------------------
# SSH prerequisites
# ------------------------------------------------------------

.PHONY: ac86u-certs-prereqs-ssh

ac86u-certs-prereqs-ssh: $(STAMP_SOPS)
	@ssh $(SSH_OPTS) \
		-p $(SSH_PORT_AC86U) \
		$(SSH_USER_AC86U)@$(LAN_AC86U) true 2>/dev/null || { \
		echo "❌ SSH key authentication to AC86U failed"; \
		exit 1; \
	}

# ------------------------------------------------------------
# Prepare router-side tooling
# ------------------------------------------------------------

.PHONY: ac86u-certs-deploy-script

ac86u-certs-deploy-script: $(STAMP_SOPS)
	@rc=0; \
	$(call WITH_SECRETS, \
		$(INSTALL_FILE_IF_CHANGED) "" "" "$(SRC_SCRIPTS)/certs-deploy.sh" \
			"$(LAN_AC86U)" "$(SSH_PORT_AC86U)" "/jffs/scripts/certs-deploy.sh" \
			$(ROUTER_SCRIPTS_OWNER) $(ROUTER_SCRIPTS_GROUP) $(ROUTER_SCRIPTS_MODE) \
	) || rc=$$?; \
	case "$$rc" in \
		0|3|'') exit 0 ;; \
		*[!0-9]*) exit 0 ;; \
		*) exit "$$rc" ;; \
	esac
# ------------------------------------------------------------
# Prepare
# ------------------------------------------------------------

.PHONY: ac86u-certs-prepare

ac86u-certs-prepare: install-all ac86u-certs-deploy-script $(STAMP_SOPS)
	@echo "📦 Preparing AC86U certificate deployment"

# ------------------------------------------------------------
# Deploy
# ------------------------------------------------------------

.PHONY: ac86u-certs-deploy

ac86u-certs-deploy: \
	ac86u-certs-prereqs-ssh \
	ac86u-certs-prepare \
	$(STAMP_CERTS_CANONICAL)
	@echo "🔐 Deploying ECC TLS to AC86U"; \
	$(call WITH_SECRETS, \
		$(run_as_root) env \
			SSL_KEY_ECC="$(SSL_KEY_ECC)" \
			SSL_CERT_ECC="$(SSL_CERT_ECC)" \
			SSL_CHAIN_ECC="$(SSL_CHAIN_ECC)" \
			SSL_FULLCHAIN_ECC="$(SSL_CHAIN_ECC)" \
			SSL_CANONICAL_DIR="$(SSL_CANONICAL_DIR)" \
			DOMAIN="$(DOMAIN)" \
			ROUTER_ADDR="$(LAN_AC86U)" \
			ROUTER_SSH_PORT="$(SSH_PORT_AC86U)" \
			SSH_USER_ROUTER="$(SSH_USER_AC86U)" \
			SSH_OPTS="$(SSH_OPTS)" \
			$(INSTALL_PATH)/deploy_certificates.sh deploy router \
	)

# ------------------------------------------------------------
# Validate
# ------------------------------------------------------------

.PHONY: ac86u-certs-validate

ac86u-certs-validate:
	@$(call WITH_SECRETS, \
		$(run_as_root) env \
			SSL_CANONICAL_DIR="$(SSL_CANONICAL_DIR)" \
			DOMAIN="$(DOMAIN)" \
			ROUTER_ADDR="$(LAN_AC86U)" \
			ROUTER_SSH_PORT="$(SSH_PORT_AC86U)" \
			SSH_USER_ROUTER="$(SSH_USER_AC86U)" \
			$(CERTS_DEPLOY) validate router \
	)

# ------------------------------------------------------------
# Status
# ------------------------------------------------------------

.PHONY: ac86u-certs-status

ac86u-certs-status:
	@ssh -p $(SSH_PORT_AC86U) \
		$(SSH_USER_AC86U)@$(LAN_AC86U) \
		'openssl x509 -in /etc/cert.pem -noout -subject -issuer'

# ------------------------------------------------------------
# Legacy compatibility targets
# ------------------------------------------------------------

.PHONY: deploy-ac86u

deploy-ac86u: ac86u-certs-deploy
	@echo "🔄 AC86U certificate deploy completed"

.PHONY: validate-ac86u

validate-ac86u: ac86u-certs-validate

.PHONY: ac86u-logs

ac86u-logs:
	@ssh -p $(SSH_PORT_AC86U) \
		$(SSH_USER_AC86U)@$(LAN_AC86U) \
		'logread -f'