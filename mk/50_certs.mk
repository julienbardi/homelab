# ============================================================
# mk/50_certs.mk — Certificate orchestration
# ============================================================
# --------------------------------------------------------------------
# CONTRACT:
# - Uses run_as_root inherited from mk/01_common.mk
# - All recipes must call $(run_as_root) with argv tokens.
# - All recipes are executed by /bin/sh
# - Escape $ → $$ (Make expands $ first)
# - Do NOT escape shell operators: && || | > <
# - Do not wrap entire commands in quotes
# - Use line continuations (\) only for readability
# - Keeps all cert watchers passive until a cert actually changes
# --------------------------------------------------------------------

CERTS_CREATE       := /usr/local/bin/certs-create.sh
CERTS_DEPLOY       := /usr/local/bin/certs-deploy.sh
GEN_CLIENT_CERT    := /usr/local/bin/generate-client-cert.sh
GEN_CLIENT_WRAPPER := /usr/local/bin/gen-client-cert-wrapper.sh

SCRIPT_DIR := $(HOMELAB_DIR)/scripts
DEPLOY     := $(SCRIPT_DIR)/deploy_certificates.sh

# --------------------------------------------------------------------
# Idempotent internal CA creation and deployment helpers
# --------------------------------------------------------------------
SSL_CANONICAL_DIR ?= /var/lib/ssl/canonical
CA_KEY := /etc/ssl/private/ca/homelab_bardi_CA.key
CA_PUB := /etc/ssl/certs/homelab_bardi_CA.pem
CANON_CA := $(SSL_CANONICAL_DIR)/ca.cer
CADDY_DEPLOY_DIR ?= /etc/ssl/caddy

.PHONY: certs-create certs-deploy certs-ensure certs-status

# Create CA (idempotent). Uses EC P-384 by default.
certs-create: $(CERTS_CREATE)
	@$(run_as_root) $(CERTS_CREATE)

.PHONY: gen-client-cert
gen-client-cert: $(GEN_CLIENT_WRAPPER)
	@if [ -z "$(CN)" ]; then \
	  echo "[make] usage: make gen-client-cert CN=<name> [FORCE=1]"; exit 1; \
	fi
	@FORCE_FLAG=''; if [ "$(FORCE)" = "1" ]; then FORCE_FLAG="--force"; fi; \
	$(GEN_CLIENT_WRAPPER) "$(CN)" "$(run_as_root)" "$(SCRIPT_DIR)" "$$FORCE_FLAG"

# Deploy CA public cert into canonical store and caddy deploy dir (idempotent)
certs-deploy: certs-create $(CERTS_DEPLOY)
	@CONF_FORCE=$(CONF_FORCE) $(run_as_root) $(CERTS_DEPLOY) 2>/dev/null
	@echo "🔐 Certificates deployed"

# Ensure CA exists and is deployed (used by other Makefiles)
certs-ensure: certs-deploy
	@echo "🔁 certificates ensured"

# Status: list CA and client certs
certs-status:
	@echo "CA private: $(CA_KEY)"; ls -l "$(CA_KEY)" || true
	@echo "CA public (canonical): $(CANON_CA)"; ls -l "$(CANON_CA)" || true
	@echo "Caddy CA: $(CADDY_DEPLOY_DIR)/homelab_bardi_CA.pem"; ls -l "$(CADDY_DEPLOY_DIR)/homelab_bardi_CA.pem" || true
	@echo "Client store: /etc/ssl/caddy/clients"; ls -l /etc/ssl/caddy/clients || true

# Check CA expiry (prints human-readable expiry and days left)
.PHONY: certs-expiry
certs-expiry:
	@if [ -f "$(CA_PUB)" ]; then \
	  echo "🔍 CA public cert: $(CA_PUB)"; \
	  $(run_as_root) openssl x509 -in "$(CA_PUB)" -noout -enddate -subject; \
	  expiry=$$($(run_as_root) openssl x509 -in "$(CA_PUB)" -noout -enddate | cut -d= -f2); \
	  expiry_ts=$$(date -d "$$expiry" +%s); now_ts=$$(date +%s); \
	  days_left=$$(( (expiry_ts - now_ts) / 86400 )); \
	  echo "⏳ days until CA expiry: $$days_left"; \
	else \
	  echo "❌ CA public cert missing: $(CA_PUB)"; exit 2; \
	fi

# Rotate CA (dangerous: creates a new CA and lists clients that must be reissued)
.PHONY: certs-rotate
certs-rotate: $(CERTS_CREATE) $(CERTS_DEPLOY) $(GEN_CLIENT_CERT)
	@echo "🔥 ROTATE CA - this will create a new CA and invalidate existing client certs"; \
	read -p "Type YES to proceed: " confirm && [ "$$confirm" = "YES" ] || (echo "aborting"; exit 1); \
	# exclusive lock to avoid concurrent runs
	$(run_as_root) bash -c 'exec 9>/var/lock/certs-rotate.lock || exit 1; flock -n 9 || { echo "another certs-rotate is running"; exit 1; }; \
	set -euo pipefail; \
	# vars
	CA_KEY="$(CA_KEY)"; CA_PUB="$(CA_PUB)"; CANON_CA="$(CANON_CA)"; CLIENT_DIR="/etc/ssl/caddy/clients"; BACKUP_DIR="/root/ca-backups"; TAG="certs-rotate"; \
	mkdir -p "$$BACKUP_DIR"; chmod 0700 "$$BACKUP_DIR"; \
	ts=$$(date -u +"%Y%m%dT%H%M%SZ"); \
	backup_plain="$$BACKUP_DIR/homelab_bardi_CA.$$ts.tar.gz"; \
	logger -t "$$TAG" -p user.info "Starting CA rotation; creating backup if present"; \
	# backup existing CA files if present
	if [ -f "$$CA_KEY" ] || [ -f "$$CA_PUB" ]; then \
	  tar -czf "$$backup_plain" --absolute-names --warning=no-file-changed "$$CA_KEY" "$$CA_PUB" 2>/dev/null || true; \
	  chmod 0600 "$$backup_plain" || true; \
	  logger -t "$$TAG" -p user.info "Backup created: $$backup_plain"; \
	else \
	  logger -t "$$TAG" -p user.info "No existing CA files found to backup"; \
	fi; \
	# move originals aside into backup dir
	if [ -f "$$CA_KEY" ]; then mv -f "$$CA_KEY" "$$BACKUP_DIR/homelab_bardi_CA.key.$$ts"; fi; \
	if [ -f "$$CA_PUB" ]; then mv -f "$$CA_PUB" "$$BACKUP_DIR/homelab_bardi_CA.pem.$$ts"; fi; \
	logger -t "$$TAG" -p user.info "Old CA files moved to $$BACKUP_DIR"; \
	# create and deploy new CA via existing make targets
	logger -t "$$TAG" -p user.info "Creating new CA"; \
	$(run_as_root) $(CERTS_CREATE) || { logger -t "$$TAG" -p user.err "certs-create failed"; exit 1; }; \
	CONF_FORCE=$(CONF_FORCE) $(run_as_root) $(CERTS_DEPLOY) || { logger -t "$$TAG" -p user.err "certs-deploy failed"; exit 1; }; \
	logger -t "$$TAG" -p user.info "New CA created and deployed"; \
	# list affected clients
	clients=$$(ls -1 "$$CLIENT_DIR"/*.p12 2>/dev/null | xargs -n1 basename 2>/dev/null | sed "s/\.p12$$//") || true; \
	if [ -z "$$clients" ]; then logger -t "$$TAG" -p user.info "No client .p12 files found (no reissue needed)"; else logger -t "$$TAG" -p user.info "Clients to reissue: $$clients"; fi; \
	# offer automatic reissue if helper exists
	if [ -n "$$clients" ]; then \
	  if [ ! -x "$(GEN_CLIENT_CERT)" ]; then \
		logger -t "$$TAG" -p user.err "generate-client-cert.sh not found or not executable; cannot reissue automatically"; \
		echo "generate-client-cert.sh missing or not executable; reissue manually"; \
	  else \
		read -p "Reissue all listed clients now using new CA? Type YES to proceed: " r && [ "$$r" = "YES" ] || { logger -t "$$TAG" -p user.info "Skipping automatic reissue"; exit 0; }; \
		logger -t "$$TAG" -p user.info "Reissuing clients"; \
		for u in $$clients; do \
		  logger -t "$$TAG" -p user.info "Reissuing $$u"; \
		  $(run_as_root) $(GEN_CLIENT_CERT) "$$u" --force || logger -t "$$TAG" -p user.err "Failed to reissue $$u"; \
		done; \
		logger -t "$$TAG" -p user.info "Automatic reissue complete; admin must securely deliver new .p12 files to users"; \
	  fi; \
	fi; \
	# install expiry monitor (journal) using secure temp files under /root
	read -p "Install CA expiry monitor (weekly -> systemd journal)? Type YES to install: " m && [ "$$m" = "YES" ] || { logger -t "$$TAG" -p user.info "Expiry monitor not installed"; exit 0; }; \
	logger -t "$$TAG" -p user.info "Installing expiry monitor (script + systemd timer -> journal)"; \
	tmp_script=$$(mktemp /root/certs-expiry-XXXXXX.sh); \
	printf "%s\n" "#!/bin/bash" "CA_PUB=\"$(CANON_CA)\"" "TAG=\"certs-expiry-check\"" "set -euo pipefail" \
	"if [ ! -f \"\$$CA_PUB\" ]; then" \
	"  logger -t \"\$$TAG\" -p user.err \"ERROR: CA public cert missing at \$$CA_PUB\"; exit 2" \
	"fi" \
	"enddate=\$$(openssl x509 -in \"\$$CA_PUB\" -noout -enddate | cut -d= -f2)" \
	"expiry_ts=\$$(date -d \"\$$enddate\" +%s)" \
	"now_ts=\$$(date +%s)" \
	"days_left=\$$(( (expiry_ts - now_ts) / 86400 ))" \
	"logger -t \"\$$TAG\" -p user.info \"CA expires on \$$enddate (days left: \$$days_left)\"" \
	"if [ \$$days_left -le 90 ]; then" \
	"  logger -t \"\$$TAG\" -p user.warn \"WARNING: CA expires in \$$days_left days\"" \
	"fi" > "$$tmp_script"; \
	chmod 0755 "$$tmp_script"; install -m 0755 "$$tmp_script" /usr/local/bin/certs-expiry-check.sh; rm -f "$$tmp_script"; \
	tmp_svc=$$(mktemp /root/certs-expiry-XXXXXX.service); \
	printf "%s\n" "[Unit]" "Description=Check CA expiry and log status to journal" "" "[Service]" "Type=oneshot" "ExecStart=/usr/local/bin/certs-expiry-check.sh" "StandardOutput=journal" "StandardError=journal" > "$$tmp_svc"; \
	install -m 0644 "$$tmp_svc" /etc/systemd/system/certs-expiry-check.service; rm -f "$$tmp_svc"; \
	tmp_timer=$$(mktemp /root/certs-expiry-XXXXXX.timer); \
	printf "%s\n" "[Unit]" "Description=Run CA expiry check weekly" "" "[Timer]" "OnCalendar=weekly" "Persistent=true" "" "[Install]" "WantedBy=timers.target" > "$$tmp_timer"; \
	install -m 0644 "$$tmp_timer" /etc/systemd/system/certs-expiry-check.timer; rm -f "$$tmp_timer"; \
	systemctl daemon-reload; systemctl enable --now certs-expiry-check.timer; \
	logger -t "$$TAG" -p user.info "Expiry monitor installed and enabled (weekly -> journal)"; \
	logger -t "$$TAG" -p user.info "View logs: journalctl -t certs-expiry-check --no-pager"; \
	# flock released on shell exit; exit 0'

########


.PHONY: issue renew prepare \
	deploy-caddy deploy-headscale deploy-dnsdist deploy-router deploy-diskstation deploy-qnap \
	validate-caddy validate-headscale validate-router validate-diskstation validate-qnap \
	all-caddy all-headscale all-router all-diskstation all-qnap \
	setup-cert-watch-% setup-cert-watch-all \
	deploy-cert-watch-% deploy-cert-watch-all \
	bootstrap-caddy bootstrap-headscale bootstrap-router bootstrap-diskstation bootstrap-qnap \
	bootstrap-all

# Base actions
issue:
	@$(run_as_root) $(DEPLOY) issue || { echo "[make] ❌ issue failed"; exit 1; }

renew:
	@$(run_as_root) $(DEPLOY) renew FORCE=$(FORCE) ACME_FORCE=$(ACME_FORCE) || { echo "[make] ❌ renew failed"; exit 1; }

prepare: renew fix-acme-perms
	@$(run_as_root) $(DEPLOY) prepare || { echo "[make] ❌ prepare failed"; exit 1; }

# Deploy targets
define deploy_with_status
	@$(run_as_root) $(DEPLOY) deploy $(1) 2>/dev/null
	@echo "🔄 Certificate deploy requested → $(1)"
endef

deploy-caddy: prepare
	$(call deploy_with_status,caddy)

deploy-headscale: prepare
	$(call deploy_with_status,headscale)

deploy-dnsdist: prepare
	$(call deploy_with_status,dnsdist)

deploy-router: prepare
	$(call deploy_with_status,router)

deploy-diskstation: prepare
	$(call deploy_with_status,diskstation)

deploy-qnap: prepare
	$(call deploy_with_status,qnap)

# Validate targets
define validate_with_status
	@$(run_as_root) $(DEPLOY) validate $(1)
	@echo "🔁 $(1) validation OK"
endef

validate-caddy:       $(call validate_with_status,caddy)
validate-headscale:   $(call validate_with_status,headscale)
validate-router:      $(call validate_with_status,router)
validate-diskstation: $(call validate_with_status,diskstation)
validate-qnap:        $(call validate_with_status,qnap)

# All-in-one targets (pattern rule: renew + prepare + deploy + validate)
all-caddy:       renew prepare deploy-caddy       validate-caddy
all-headscale:   renew prepare deploy-headscale   validate-headscale
all-router:      renew prepare deploy-router      validate-router
all-diskstation: renew prepare deploy-diskstation validate-diskstation
all-qnap:        renew prepare deploy-qnap        validate-qnap

# Cert watch setup targets
setup-cert-watch-%:
	@$(run_as_root) install -m 0644 scripts/systemd/cert-reload@.service \
		/etc/systemd/system/cert-reload@.service && \
	if [ "$*" = "dnsdist" ]; then \
		$(run_as_root) install -d -m 0755 \
			/etc/systemd/system/cert-reload@dnsdist.service.d && \
		$(run_as_root) install -m 0644 \
			scripts/systemd/cert-reload@dnsdist.service.d/override.conf \
			/etc/systemd/system/cert-reload@dnsdist.service.d/override.conf ; \
	fi && \
	$(run_as_root) install -m 0644 \
		scripts/systemd/$*-cert.path \
		/etc/systemd/system/$*-cert.path && \
	$(run_as_root) systemctl daemon-reload && \
	$(run_as_root) systemctl enable $*-cert.path

# FIX: remote machines are NOT local systemd services; remove them from watchers
setup-cert-watch-all: \
	setup-cert-watch-caddy \
	setup-cert-watch-dnsdist \
	setup-cert-watch-headscale

# Bootstrap combos
define bootstrap_with_status
	@$(MAKE) setup-cert-watch-$(1)
	@$(MAKE) all-$(1)
	@echo "🚀 $(1) bootstrapped"
endef

bootstrap-caddy:         $(call bootstrap_with_status,caddy)
bootstrap-headscale:     $(call bootstrap_with_status,headscale)
bootstrap-router:        $(call bootstrap_with_status,router)
bootstrap-diskstation:   $(call bootstrap_with_status,diskstation)
bootstrap-qnap:          $(call bootstrap_with_status,qnap)

# FIX: bootstrap-all wires only LOCAL watchers; no remote hosts here
bootstrap-all: \
	setup-cert-watch-caddy all-caddy \
	setup-cert-watch-headscale

# Cert watch deploy targets
define deploy_cert_watch
	@$(run_as_root) install -m 0644 scripts/systemd/cert-reload@.service /etc/systemd/system/cert-reload@.service
	@$(run_as_root) install -m 0644 scripts/systemd/$(1)-cert.path /etc/systemd/system/$(1)-cert.path
	@$(run_as_root) systemctl daemon-reload
	@$(run_as_root) systemctl enable $(1)-cert.path
endef

deploy-cert-watch-%:
	$(call deploy_cert_watch,$*)

# FIX: deploy only LOCAL watcher units; remove diskstation/qnap/router
deploy-cert-watch-all: \
	deploy-cert-watch-caddy \
	deploy-cert-watch-dnsdist \
	deploy-cert-watch-headscale
