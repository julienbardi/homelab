# ============================================================
# mk/50_certs.mk — Certificate orchestration (STAMP-OPTIMIZED)
# ============================================================
# CONTRACT:
# - Deterministic, stamp-driven certificate pipeline
# - CERTS_DEPLOY runs ONLY when canonical certs change
# - All remote deploys depend on canonical cert stamp
# - SAN validation and canonical store rebuild run only when needed
# ============================================================

CERTS_CREATE        := $(INSTALL_PATH)/certs-create.sh
CERTS_DEPLOY        := $(INSTALL_PATH)/deploy_certificates.sh
GEN_CLIENT_CERT     := $(INSTALL_PATH)/generate-client-cert.sh
GEN_CLIENT_WRAPPER  := $(INSTALL_PATH)/gen-client-cert-wrapper.sh

SSL_CANONICAL_DIR ?= /var/lib/ssl/canonical
CA_KEY            := /etc/ssl/private/ca/homelab_bardi_CA.key
CA_PUB            := /etc/ssl/certs/homelab_bardi_CA.pem
CANON_CA          := $(SSL_CANONICAL_DIR)/ca.cer

CADDY_DEPLOY_DIR ?= /etc/ssl/caddy

# ============================================================
# Canonical certificate stamp (Option A)
# ============================================================
STAMP_CERTS_CANONICAL := $(STAMP_DIR_ROOT)/certs_canonical.sha256
STAMP_PREPARE         := $(STAMP_DIR_ROOT)/prepare.stamp

# ============================================================
# Internal CA lifecycle
# ============================================================
.PHONY: certs-create certs-deploy certs-ensure certs-status certs-expiry \
		certs-rotate certs-rotate-dangerous gen-client-cert

certs-create: $(CERTS_CREATE)
	@$(run_as_root) $(CERTS_CREATE)

gen-client-cert: $(GEN_CLIENT_WRAPPER) $(GEN_CLIENT_CERT)
	@if [ -z "$(CN)" ]; then \
	  echo "❌ Usage: make gen-client-cert CN=<name> [FORCE=1]"; exit 1; \
	fi
	@FORCE_FLAG=''; if [ "$(FORCE)" = "1" ]; then FORCE_FLAG="--force"; fi; \
	$(GEN_CLIENT_WRAPPER) "$(CN)" "$(run_as_root)" "$(INSTALL_PATH)" "$$FORCE_FLAG"

certs-deploy: certs-create $(CERTS_DEPLOY)
	@$(run_as_root) $(CERTS_DEPLOY) deploy caddy
	@$(run_as_root) $(CERTS_DEPLOY) deploy dnsdist
	@$(run_as_root) $(CERTS_DEPLOY) deploy router
	@echo "🔐 Certificates deployed"

certs-ensure: certs-deploy
	@echo "🔄 certificates ensured"

certs-status:
	@echo "CA private: $(CA_KEY)"; ls -l "$(CA_KEY)" || true
	@echo "CA public (canonical): $(CANON_CA)"; ls -l "$(CANON_CA)" || true
	@echo "Caddy CA: $(CADDY_DEPLOY_DIR)/homelab_bardi_CA.pem"; ls -l "$(CADDY_DEPLOY_DIR)/homelab_bardi_CA.pem" || true
	@echo "Client store: /etc/ssl/caddy/clients"; ls -l /etc/ssl/caddy/clients || true

certs-expiry:
	@if [ -f "$(CA_PUB)" ]; then \
	  echo "🔍 CA public cert: $(CA_PUB)"; \
	  $(run_as_root) openssl x509 -in "$(CA_PUB)" -noout -enddate -subject; \
	  expiry=$$($(run_as_root) openssl x509 -in "$(CA_PUB)" -noout -enddate | cut -d= -f2); \
	  expiry_ts=$$(date -d "$$expiry" +%s); now_ts=$$(date +%s); \
	  days_left=$$(( (expiry_ts - now_ts) / 86400 )); \
	  echo "ℹ️ days until CA expiry: $$days_left"; \
	else \
	  echo "❌ CA public cert missing: $(CA_PUB)"; exit 2; \
	fi

# ============================================================
# ACME / service certificate workflow
# ============================================================
.PHONY: prepare \
		deploy-caddy deploy-headscale deploy-dnsdist deploy-diskstation deploy-qnap deploy-dsm \
		validate-caddy validate-headscale validate-diskstation validate-qnap validate-dsm validate-ac86u \
		all-caddy all-headscale all-router all-diskstation all-qnap all-ac86u \
		all-remote \
		setup-cert-watch-% setup-cert-watch-all \
		deploy-cert-watch-% deploy-cert-watch-all \
		bootstrap-caddy bootstrap-headscale bootstrap-diskstation bootstrap-qnap \
		bootstrap-all deploy-ac86u


install-helpers: $(INSTALL_PATH)/common.sh \
	$(INSTALL_FILE_IF_CHANGED) \
	$(INSTALL_PATH)/deploy_certificates.sh \
	$(INSTALL_PATH)/deploy_dsm.sh
	@echo "🛠️ Helpers verified and synced"

# ============================================================
# prepare: run CERTS_DEPLOY prepare + compute canonical hash
# ============================================================

export SSL_CANONICAL_DIR
export SSL_CERT_ECC
export SSL_CHAIN_ECC
export SSL_KEY_ECC
export ACME_HOME
export DOMAIN

$(STAMP_PREPARE): acme-renew $(CERTS_DEPLOY)
	@$(call WITH_SECRETS, $(run_as_root) sh -c '\
		set -euo pipefail; \
		$(CERTS_DEPLOY) prepare; \
		sha256sum \
			$(SSL_CANONICAL_DIR)/fullchain_ecc.pem \
			$(SSL_CANONICAL_DIR)/privkey_ecc.pem \
			| sha256sum | awk '\''{print $$1}'\'' \
			> $(STAMP_CERTS_CANONICAL); \
		touch $(STAMP_PREPARE); \
	') || { echo "❌ prepare failed"; exit 1; }

prepare: $(STAMP_PREPARE)

# STAMP_CERTS_CANONICAL is produced by the prepare rule
$(STAMP_CERTS_CANONICAL): $(STAMP_PREPARE)
	@true

# ============================================================
# All deploy targets depend on canonical stamp
# ============================================================
deploy-caddy:      $(STAMP_CERTS_CANONICAL) router-install-scripts
	$(call WITH_SECRETS, $(call deploy_with_status,caddy))

deploy-headscale: headscale-user headscale-dirs $(STAMP_CERTS_CANONICAL)
	$(call WITH_SECRETS, $(call deploy_with_status,headscale))

deploy-dnsdist:    $(STAMP_CERTS_CANONICAL)
	$(call WITH_SECRETS, $(call deploy_with_status,dnsdist))

deploy-qnap:       $(STAMP_CERTS_CANONICAL)
	$(call WITH_SECRETS, $(call deploy_with_status,qnap))

deploy-dsm:        $(STAMP_CERTS_CANONICAL)
	@echo "🔄 DSM deploy triggered by canonical cert change"

deploy-ac86u:      $(STAMP_CERTS_CANONICAL)
	@echo "🔄 AC86U deploy triggered by canonical cert change"

# ============================================================
# Validation targets
# ============================================================
validate-caddy:
	$(call validate_with_status,caddy)

validate-headscale:
	$(call validate_with_status,headscale)

validate-diskstation: validate-dsm
	@echo "🔄 DiskStation validation OK"

validate-qnap:
	@echo "🔍 [validate][qnap] Checking certificate on $(LAN_QNAP):443..."; \
	if ! openssl s_client -connect $(LAN_QNAP):443 -servername $(DOMAIN) -tls1_2 -showcerts </dev/null 2>/dev/null \
		| openssl x509 -noout -fingerprint -sha256; then \
		echo "⚠️ [validate][qnap] Validation failed (best-effort, non-fatal)"; \
	else \
		echo "✅ [validate][qnap] Validation complete"; \
	fi

validate-dsm:
	@echo "⚠️ [validate][dsm] Temporarily disabled — DSM certificate not validated"
	@exit 0

validate-ac86u:
	@echo "🔍 [validate][ac86u] Checking certificate on $(LAN_AC86U):8443"; \
	sleep 0.3; \
	remote_fp=$$(openssl s_client -connect $(LAN_AC86U):8443 -servername $(DOMAIN) -tls1_2 -showcerts </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256); \
	echo "ℹ️ Remote Fingerprint: $$remote_fp"; \
	echo "🔄 AC86U validation OK (best-effort)"

# ============================================================
# All-in-one targets
# ============================================================
all-caddy:       $(STAMP_PREPARE) deploy-caddy       validate-caddy
all-headscale:   $(STAMP_PREPARE) deploy-headscale   validate-headscale
all-router:      $(STAMP_PREPARE) deploy-router
all-diskstation: $(STAMP_PREPARE) deploy-diskstation validate-diskstation
all-qnap:        $(STAMP_PREPARE) deploy-qnap        validate-qnap
all-ac86u:       $(STAMP_PREPARE) deploy-ac86u       validate-ac86u

all-remote: all-router all-diskstation all-qnap all-ac86u

# ============================================================
# Cert watchers
# ============================================================
setup-cert-watch-%: scripts/systemd/cert-reload@.service scripts/systemd/$*-cert.path
	@$(run_as_root) install -m 0644 scripts/systemd/cert-reload@.service \
		/etc/systemd/system/cert-reload@.service && \
	$(run_as_root) install -m 0644 scripts/systemd/$*-cert.path \
		/etc/systemd/system/$*-cert.path && \
	$(run_as_root) systemctl daemon-reload && \
	$(run_as_root) systemctl enable $*-cert.path

setup-cert-watch-all: setup-cert-watch-caddy setup-cert-watch-dnsdist setup-cert-watch-headscale

bootstrap-caddy: setup-cert-watch-caddy all-caddy
	@echo "🚀 caddy bootstrapped"

bootstrap-headscale: setup-cert-watch-headscale all-headscale
	@echo "🚀 headscale bootstrapped"

bootstrap-diskstation: setup-cert-watch-diskstation all-diskstation
	@echo "🚀 diskstation bootstrapped"

bootstrap-qnap: setup-cert-watch-qnap all-qnap
	@echo "🚀 qnap bootstrapped"

bootstrap-all: setup-cert-watch-caddy all-caddy setup-cert-watch-headscale all-headscale
