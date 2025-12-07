# ============================================================
# mk/50_certs.mk — Certificate orchestration
# ============================================================
# --------------------------------------------------------------------
# CONTRACT:
# - Defines run_as_root := ./bin/run-as-root
# - All recipes must call $(run_as_root) with argv tokens.
# - Do not wrap entire command in quotes.
# - Escape operators (\>, \|, \&\&, \|\|) so they survive Make parsing.
# --------------------------------------------------------------------
SCRIPT_DIR := ${HOMELAB_DIR}/scripts
DEPLOY     := $(SCRIPT_DIR)/setup/deploy_certificates.sh

# --------------------------------------------------------------------
# Idempotent internal CA creation and deployment helpers
# --------------------------------------------------------------------
REPO_ROOT ?= $(HOME)/src/homelab
SSL_CANONICAL_DIR ?= /var/lib/ssl/canonical
CA_KEY := /etc/ssl/private/ca/homelab_bardi_CA.key
CA_PUB := /etc/ssl/certs/homelab_bardi_CA.pem
CANON_CA := $(SSL_CANONICAL_DIR)/ca.cer
CADDY_DEPLOY_DIR ?= /etc/ssl/caddy

.PHONY: certs-create certs-deploy certs-ensure certs-status

# Create CA (idempotent). Uses EC P-384 by default.
certs-create:
	@echo "[certs] ensure CA private key + public cert exist"
	@if [ -f "$(CA_KEY)" -a -f "$(CA_PUB)" ]; then \
	  echo "[certs] CA already exists: $(CA_PUB)"; \
	else \
	  sudo mkdir -p /etc/ssl/private/ca; sudo chmod 700 /etc/ssl/private/ca; \
	  echo "[certs] generating CA private key $(CA_KEY)"; \
	  sudo openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 -out "$(CA_KEY)"; \
	  sudo chmod 0600 "$(CA_KEY)"; \
	  echo "[certs] generating CA public cert $(CA_PUB)"; \
	  sudo openssl req -x509 -new -key "$(CA_KEY)" -days 3650 -sha256 \
		-subj "/CN=homelab-bardi-CA/O=bardi.ch/OU=homelab" -out "$(CA_PUB)"; \
	  sudo chmod 0644 "$(CA_PUB)"; \
	fi

.PHONY: gen-client-cert
gen-client-cert:
	@if [ -z "$(CN)" ]; then \
	  echo "[make] usage: make gen-client-cert CN=<name> [FORCE=1]"; exit 1; \
	fi
	@FORCE_FLAG=''; if [ "$(FORCE)" = "1" ]; then FORCE_FLAG="--force"; fi; \
	./scripts/gen-client-cert-wrapper.sh "$(CN)" "$(run_as_root)" "$(SCRIPT_DIR)" "$$FORCE_FLAG"



# Deploy CA public cert into canonical store and caddy deploy dir (idempotent)
certs-deploy: certs-create
	@echo "[certs] deploying CA public cert to canonical store and caddy"
	@sudo mkdir -p "$(SSL_CANONICAL_DIR)"; \
	  sudo install -m 0644 "$(CA_PUB)" "$(CANON_CA)"; \
	  sudo chown root:root "$(CANON_CA)"; \
	  sudo mkdir -p "$(CADDY_DEPLOY_DIR)"; \
	  sudo install -m 0644 "$(CANON_CA)" "$(CADDY_DEPLOY_DIR)/homelab_bardi_CA.pem"; \
	  sudo chown root:root "$(CADDY_DEPLOY_DIR)/homelab_bardi_CA.pem"; \
	  echo "[certs] deployed to $(CANON_CA) and $(CADDY_DEPLOY_DIR)/homelab_bardi_CA.pem"

# Ensure CA exists and is deployed (used by other Makefiles)
certs-ensure: certs-deploy
	@echo "[certs] ensure complete"

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
	  echo "[certs] CA public cert: $(CA_PUB)"; \
	  sudo openssl x509 -in "$(CA_PUB)" -noout -enddate -subject; \
	  expiry=$$(sudo openssl x509 -in "$(CA_PUB)" -noout -enddate | cut -d= -f2); \
	  expiry_ts=$$(date -d "$$expiry" +%s); now_ts=$$(date +%s); \
	  days_left=$$(( (expiry_ts - now_ts) / 86400 )); \
	  echo "[certs] days until CA expiry: $$days_left"; \
	else \
	  echo "[certs] CA public cert missing: $(CA_PUB)"; exit 2; \
	fi

# Rotate CA (dangerous: creates a new CA and lists clients that must be reissued)
.PHONY: certs-rotate
certs-rotate:
	@echo "[certs] ROTATE CA - this will create a new CA and invalidate existing client certs"; \
	read -p "Type YES to proceed: " confirm && [ "$$confirm" = "YES" ] || (echo "aborting"; exit 1); \
	# exclusive lock to avoid concurrent runs
	sudo bash -c 'exec 9>/var/lock/certs-rotate.lock || exit 1; flock -n 9 || { echo "another certs-rotate is running"; exit 1; }; \
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
	$(MAKE) FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) certs-create || { logger -t "$$TAG" -p user.err "certs-create failed"; exit 1; }; \
	$(MAKE) FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) certs-deploy || { logger -t "$$TAG" -p user.err "certs-deploy failed"; exit 1; }; \
	logger -t "$$TAG" -p user.info "New CA created and deployed"; \
	# list affected clients
	clients=$$(ls -1 "$$CLIENT_DIR"/*.p12 2>/dev/null | xargs -n1 basename 2>/dev/null | sed "s/\.p12$$//") || true; \
	if [ -z "$$clients" ]; then logger -t "$$TAG" -p user.info "No client .p12 files found (no reissue needed)"; else logger -t "$$TAG" -p user.info "Clients to reissue: $$clients"; fi; \
	# offer automatic reissue if helper exists
	if [ -n "$$clients" ]; then \
	  if [ ! -x "$(SCRIPT_DIR)/generate-client-cert.sh" ] && [ ! -x "scripts/generate-client-cert.sh" ]; then \
		logger -t "$$TAG" -p user.err "generate-client-cert.sh not found or not executable; cannot reissue automatically"; \
		echo "generate-client-cert.sh missing or not executable; reissue manually"; \
	  else \
		read -p "Reissue all listed clients now using new CA? Type YES to proceed: " r && [ "$$r" = "YES" ] || { logger -t "$$TAG" -p user.info "Skipping automatic reissue"; exit 0; }; \
		logger -t "$$TAG" -p user.info "Reissuing clients"; \
		for u in $$clients; do \
		  logger -t "$$TAG" -p user.info "Reissuing $$u"; \
		  if [ -x "$(SCRIPT_DIR)/generate-client-cert.sh" ]; then sudo "$(SCRIPT_DIR)/generate-client-cert.sh" "$$u" --force || logger -t "$$TAG" -p user.err "Failed to reissue $$u"; else sudo scripts/generate-client-cert.sh "$$u" --force || logger -t "$$TAG" -p user.err "Failed to reissue $$u"; fi; \
		done; \
		logger -t "$$TAG" -p user.info "Automatic reissue complete; admin must securely deliver new .p12 files to users"; \
	  fi; \
	fi; \
	# install expiry monitor (journal) using secure temp files under /root
	read -p "Install CA expiry monitor (weekly -> systemd journal)? Type YES to install: " m && [ "$$m" = "YES" ] || { logger -t "$$TAG" -p user.info "Expiry monitor not installed"; exit 0; }; \
	logger -t "$$TAG" -p user.info "Installing expiry monitor (script + systemd timer -> journal)"; \
	tmp_script=$$(mktemp /root/certs-expiry-XXXXXX.sh); \
	printf '%s\n' '#!/bin/bash' "CA_PUB=\"$(CANON_CA)\"" "TAG=\"certs-expiry-check\"" 'set -euo pipefail' \
	'if [ ! -f "$CA_PUB" ]; then' \
	'  logger -t "$TAG" -p user.err "ERROR: CA public cert missing at $CA_PUB"; exit 2' \
	'fi' \
	'enddate=$$(openssl x509 -in "$CA_PUB" -noout -enddate | cut -d= -f2)' \
	'expiry_ts=$$(date -d "$enddate" +%s)' \
	'now_ts=$$(date +%s)' \
	'days_left=$$(( (expiry_ts - now_ts) / 86400 ))' \
	'logger -t "$TAG" -p user.info "CA expires on $enddate (days left: $days_left)"' \
	'if [ $$days_left -le 90 ]; then' \
	'  logger -t "$TAG" -p user.warn "WARNING: CA expires in $$days_left days"' \
	'fi' > "$$tmp_script"; \
	chmod 0755 "$$tmp_script"; install -m 0755 "$$tmp_script" /usr/local/bin/certs-expiry-check.sh; rm -f "$$tmp_script"; \
	tmp_svc=$$(mktemp /root/certs-expiry-XXXXXX.service); \
	printf '%s\n' '[Unit]' 'Description=Check CA expiry and log status to journal' '' '[Service]' 'Type=oneshot' 'ExecStart=/usr/local/bin/certs-expiry-check.sh' 'StandardOutput=journal' 'StandardError=journal' > "$$tmp_svc"; \
	install -m 0644 "$$tmp_svc" /etc/systemd/system/certs-expiry-check.service; rm -f "$$tmp_svc"; \
	tmp_timer=$$(mktemp /root/certs-expiry-XXXXXX.timer); \
	printf '%s\n' '[Unit]' 'Description=Run CA expiry check weekly' '' '[Timer]' 'OnCalendar=weekly' 'Persistent=true' '' '[Install]' 'WantedBy=timers.target' > "$$tmp_timer"; \
	install -m 0644 "$$tmp_timer" /etc/systemd/system/certs-expiry-check.timer; rm -f "$$tmp_timer"; \
	systemctl daemon-reload; systemctl enable --now certs-expiry-check.timer; \
	logger -t "$$TAG" -p user.info "Expiry monitor installed and enabled (weekly -> journal)"; \
	logger -t "$$TAG" -p user.info "View logs: journalctl -t certs-expiry-check --no-pager"; \
	# flock released on shell exit; exit 0'

########


.PHONY: issue renew prepare \
	deploy-% validate-% all-% \
	setup-cert-watch-% setup-cert-watch-all \
	deploy-cert-watch-% deploy-cert-watch-all \
	bootstrap-% bootstrap-all

# Base actions
issue:
	@$(run_as_root) $(DEPLOY) issue || { echo "[make] ❌ issue failed"; exit 1; }

renew:
	@$(run_as_root) $(DEPLOY) renew FORCE=$(FORCE) || { echo "[make] ❌ renew failed"; exit 1; }

prepare: renew fix-acme-perms
	@$(run_as_root) $(DEPLOY) prepare || { echo "[make] ❌ prepare failed"; exit 1; }

# Deploy targets (pattern rule)
deploy-%: ensure-known-hosts prepare
	@$(run_as_root) $(DEPLOY) deploy $* || { echo "[make] ❌ deploy-$* failed"; exit 1; }

# Validate targets (pattern rule)
validate-%:
	@$(run_as_root) $(DEPLOY) validate $* || { echo "[make] ❌ validate-$* failed"; exit 1; }

# All-in-one targets (pattern rule: renew + prepare + deploy + validate)
all-%: renew prepare deploy-% validate-%
	@$(run_as_root) $(DEPLOY) all $* || { echo "[make] ❌ all-$* failed"; exit 1; }

# Cert watch setup targets
setup-cert-watch-%:
	@$(run_as_root) install -m 0644 scripts/systemd/cert-reload@.service /etc/systemd/system/cert-reload@.service \&& \
	$(run_as_root) install -m 0644 scripts/systemd/$*-cert.path /etc/systemd/system/$*-cert.path \&& \
	$(run_as_root) systemctl daemon-reload \&& \
	$(run_as_root) systemctl enable --now $*-cert.path

setup-cert-watch-all: \
	setup-cert-watch-caddy \
	setup-cert-watch-headscale \
	setup-cert-watch-coredns \
	setup-cert-watch-diskstation \
	setup-cert-watch-qnap

# Bootstrap combos (pattern rule)
bootstrap-%: setup-cert-watch-% all-%
	@echo "[make] bootstrap-$* complete"

bootstrap-all: \
	setup-cert-watch-caddy all-caddy \
	setup-cert-watch-headscale all-headscale \
	setup-cert-watch-coredns all-coredns \
	setup-cert-watch-diskstation all-diskstation \
	setup-cert-watch-qnap all-qnap

# Cert watch deploy targets
deploy-cert-watch-%:
	@$(run_as_root) install -m 0644 scripts/systemd/cert-reload@.service /etc/systemd/system/cert-reload@.service \&& \
	$(run_as_root) install -m 0644 scripts/systemd/$*-cert.path /etc/systemd/system/$*-cert.path \&& \
	$(run_as_root) systemctl daemon-reload \&& \
	$(run_as_root) systemctl enable --now $*-cert.path

deploy-cert-watch-all:
	@$(run_as_root) install -m 0644 scripts/systemd/cert-reload@.service /etc/systemd/system/cert-reload@.service \&& \
	$(run_as_root) install -m 0644 scripts/systemd/caddy-cert.path /etc/systemd/system/caddy-cert.path \&& \
	$(run_as_root) install -m 0644 scripts/systemd/headscale-cert.path /etc/systemd/system/headscale-cert.path \&& \
	$(run_as_root) install -m 0644 scripts/systemd/coredns-cert.path /etc/systemd/system/coredns-cert.path \&& \
	$(run_as_root) install -m 0644 scripts/systemd/diskstation-cert.path /etc/systemd/system/diskstation-cert.path \&& \
	$(run_as_root) install -m 0644 scripts/systemd/qnap-cert.path /etc/systemd/system/qnap-cert.path \&& \
	$(run_as_root) systemctl daemon-reload \&& \
	$(run_as_root) systemctl enable --now caddy-cert.path headscale-cert.path coredns-cert.path diskstation-cert.path qnap-cert.path
