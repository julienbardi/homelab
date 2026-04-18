# ============================================================
# mk/70_dnsdist.mk — dnsdist orchestration (DNS over HTTPS)
# ============================================================

# Paths & Binaries
DEPLOY_CERTS         := $(INSTALL_PATH)/deploy_certificates.sh
DNSDIST_BIN          := /usr/bin/dnsdist
DNSDIST_UNIT         := dnsdist.service

# Discovery with Override
KDIG                 ?= kdig

# Configuration (Ensuring trailing slash safety)
DNSDIST_CONF_SRC     := $(REPO_ROOT)/config/dnsdist/dnsdist.conf
DNSDIST_CONF_DST     := /etc/dnsdist/dnsdist.conf
DNSDIST_DROPIN_SRC   := $(REPO_ROOT)/scripts/systemd/dnsdist.service.d/10-no-port53.conf
DNSDIST_DROPIN_DST   := /etc/systemd/system/dnsdist.service.d/10-no-port53.conf

# TLS Material
DNSDIST_CERT_DIR     := /etc/dnsdist/certs
DNSDIST_CERT         := $(DNSDIST_CERT_DIR)/fullchain.pem
DNSDIST_KEY          := $(DNSDIST_CERT_DIR)/privkey.pem
CA_BUNDLE            ?= /var/lib/ssl/canonical/fullchain_ecc.pem

# DoH probe defaults (centralized)
DOH_HOST             := bardi.ch
DOH_PORT             := 8053
DOH_ADDR             := 127.0.0.1
DOH_TEST_NAME        ?= $(DOMAIN)
DOH_TIMEOUT          := 5
DOH_TLS_CA           := $(CA_BUNDLE)
DOH_TLS_HOST         := $(DOH_HOST)
KDIG_ARGS            := +https +tls-ca=$(DOH_TLS_CA) +tls-hostname=$(DOH_TLS_HOST) +time=$(DOH_TIMEOUT)
# Map SNI host to loopback so TLS validation uses the real certificate served for DOH_HOST
# This ensures the client presents the correct SNI and validates the cert chain.
CURL_RESOLVE         := --resolve $(DOH_HOST):$(DOH_PORT):$(DOH_ADDR)

# Commands
DNSDIST_RESTART_CMD  := $(run_as_root) systemctl restart $(DNSDIST_UNIT)

.PHONY: \
	dnsdist \
	dnsdist-install dnsdist-config dnsdist-enable dnsdist-validate \
	dnsdist-status dnsdist-systemd-dropin \
	deploy-dnsdist-certs install-kdig \
	assert-dnsdist-certs assert-dnsdist-running \
	check-dnsdist-doh-local check-dnsdist-doh-listener check-dnsdist-systemd

# --------------------------------------------------------------------
# Dependencies & Setup
# --------------------------------------------------------------------

install-kdig:
	@$(call apt_install,kdig,dnsutils)

assert-dnsdist-certs: ensure-run-as-root
	@$(run_as_root) sh -eu -c 'for f in "$(DNSDIST_CERT)" "$(DNSDIST_KEY)"; do \
		[ -r "$$f" ] || { echo "❌ Missing/unreadable: $$f"; exit 1; }; \
	done'
	@echo "✅ TLS material present"

# --------------------------------------------------------------------
# Implementation Details (Idempotent)
# --------------------------------------------------------------------

dnsdist-config: dnsdist-install ensure-run-as-root
	@set -eu; \
	$(run_as_root) install -d -m 0750 -o root -g _dnsdist /etc/dnsdist; \
	rc=0; \
	$(run_as_root) env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(INSTALL_FILE_IF_CHANGED) -q \
		"" "" "$(DNSDIST_CONF_SRC)" \
		"" "" "$(DNSDIST_CONF_DST)" \
		"$(ROOT_UID)" "$(ROOT_GID)" "0644" || rc=$$?; \
	[ "$$rc" -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ] && { \
		echo "🔄 dnsdist.conf updated, restarting..."; \
		$(DNSDIST_RESTART_CMD); \
	} || { [ "$$rc" -eq 0 ] || exit "$$rc"; }

dnsdist-systemd-dropin: ensure-run-as-root
	@set -eu; \
	$(run_as_root) install -d /etc/systemd/system/dnsdist.service.d; \
	rc=0; \
	$(run_as_root) env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(INSTALL_FILE_IF_CHANGED) -q \
		"" "" "$(DNSDIST_DROPIN_SRC)" \
		"" "" "$(DNSDIST_DROPIN_DST)" \
		"$(ROOT_UID)" "$(ROOT_GID)" "0644" || rc=$$?; \
	if [ "$$rc" -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		$(run_as_root) systemctl daemon-reload; \
		echo "🔄 Systemd drop-in updated, restarting..."; \
		$(DNSDIST_RESTART_CMD); \
	fi

# canonical store and stamp
CANONICAL_DIR := /var/lib/ssl/canonical
CANONICAL_SUM := $(CANONICAL_DIR)/.lastsum

.PHONY: deploy-dnsdist-certs

# deploy depends on the stamp so deploy runs only when canonical store changed
deploy-dnsdist-certs: acme-renew-all install-all $(HOMELAB_ENV_DST) $(DEPLOY_CERTS) $(CANONICAL_SUM) dnsdist-config ensure-run-as-root

# Robust checksum + deploy (atomic stamp write)
$(CANONICAL_SUM): $(DEPLOY_CERTS)
	@set -eu; \
	if [ ! -d "$(CANONICAL_DIR)" ]; then \
	  echo "⚠️  canonical dir missing: $(CANONICAL_DIR)"; exit 1; \
	fi; \
	if ! command -v sha256sum >/dev/null 2>&1; then \
	  echo "❌ sha256sum not found"; exit 1; \
	fi; \
	nfiles=$$($(run_as_root) sh -c "find '$(CANONICAL_DIR)' -type f -print -quit | wc -l"); \
	if [ "$$nfiles" -eq 0 ]; then \
	  echo "⚠️  canonical store empty: $(CANONICAL_DIR)"; \
	  tmp=$$(mktemp); printf "%s\n" "" > "$$tmp"; $(run_as_root) mv "$$tmp" "$(CANONICAL_SUM)"; \
	  exit 0; \
	fi; \
	sum=$$($(run_as_root) sh -c "find '$(CANONICAL_DIR)' -type f -exec sha256sum {} + 2>/dev/null | sort | sha256sum | cut -d' ' -f1"); \
	old=""; [ -f "$(CANONICAL_SUM)" ] && old=$$(cat "$(CANONICAL_SUM)"); \
	if [ "$$sum" = "$$old" ]; then \
	  echo "🔁 canonical store unchanged; skipping deploy"; \
	else \
	  echo "📦 Deploying certificates to dnsdist"; \
	  $(run_as_root) $(DEPLOY_CERTS) deploy dnsdist; \
	  tmp=$$(mktemp); printf "%s\n" "$$sum" > "$$tmp"; $(run_as_root) mv "$$tmp" "$(CANONICAL_SUM)"; \
	  echo "✅ deploy-dnsdist-certs complete"; \
	fi

# --------------------------------------------------------------------
# Verification & Status
# --------------------------------------------------------------------
dnsdist-validate: deploy-dnsdist-certs ensure-run-as-root
	@echo "🔍 Validating dnsdist configuration"
	@$(run_as_root) $(DNSDIST_BIN) --check-config

dnsdist-enable: deploy-dnsdist-certs ensure-run-as-root
	@echo "⚙️  Enabling dnsdist service"
	@$(run_as_root) systemctl enable $(DNSDIST_UNIT)

check-dnsdist-doh-local: install-kdig ensure-run-as-root
	@set -eu; \
	[ -r "$(DOH_TLS_CA)" ] || { echo "❌ Missing CA bundle: $(DOH_TLS_CA)"; exit 1; }; \
	KDIG_BIN=$$(command -v $(KDIG) 2>/dev/null || true); \
	if [ -n "$$KDIG_BIN" ]; then \
		if $(run_as_root) $$KDIG_BIN @$(DOH_ADDR) -p $(DOH_PORT) $(DOH_TEST_NAME) $(KDIG_ARGS) >/dev/null 2>&1; then \
			echo "✅ DoH resolution successful (kdig)"; \
		else \
			echo "❌ FATAL: DoH resolution failed (kdig). Diagnostic:"; \
			$(run_as_root) $$KDIG_BIN @$(DOH_ADDR) -p $(DOH_PORT) $(DOH_TEST_NAME) $(KDIG_ARGS); \
			exit 1; \
		fi; \
	else \
		echo "⚠️  kdig not found; consider installing kdig or enabling curl fallback"; \
		exit 1; \
	fi

# --------------------------------------------------------------------
# Orchestration umbrella
# --------------------------------------------------------------------

dnsdist: dnsdist-install dnsdist-systemd-dropin dnsdist-config \
	dnsdist-enable deploy-dnsdist-certs dnsdist-validate \
	assert-dnsdist-running check-dnsdist-doh-listener check-dnsdist-doh-local \
	install-kdig
	@test -z "$(VERBOSE)" || echo "🚀 dnsdist DoH frontend ready"

ci-doh-check:
	@set -eu; \
	RAND=$$(date +%s); \
	TEST="probe-$$RAND.$(DOMAIN)"; \
	KDIG_BIN=$$(command -v $(KDIG) 2>/dev/null || true); \
	if [ -z "$$KDIG_BIN" ]; then \
		echo "❌ kdig not found; install kdig for CI checks"; exit 1; \
	fi; \
	if OUT=$$($$KDIG_BIN @$(DOH_ADDR) -p $(DOH_PORT) $$TEST $(KDIG_ARGS) 2>&1); then \
		echo "$$OUT" | sed -n '1,12p'; \
		echo "✅ ci-doh-check: probe $$TEST OK (kdig)"; \
	else \
		echo "$$OUT" | sed -n '1,12p'; \
		echo "❌ ci-doh-check: probe $$TEST failed (kdig)"; exit 1; \
	fi

check-dnsdist-systemd: ensure-run-as-root
	@set -eu; \
	if ! $(run_as_root) systemctl is-active --quiet $(DNSDIST_UNIT); then \
		echo "❌ $(DNSDIST_UNIT) is not active"; \
		$(run_as_root) systemctl --no-pager status $(DNSDIST_UNIT) || true; \
		exit 1; \
	fi; \
	echo "✅ $(DNSDIST_UNIT) active"

check-dnsdist-doh-listener: ensure-run-as-root
	@set -eu; \
	if ! $(run_as_root) ss -ltn "sport = :$(DOH_PORT)" | grep -q LISTEN; then \
		echo "❌ DoH listener not present on :$(DOH_PORT)"; \
		$(run_as_root) ss -ltn | sed -n '1,120p' || true; \
		exit 1; \
	fi; \
	echo "✅ DoH listener present on :$(DOH_PORT)"

# assert depends on both checks; with `make -j` they can run in parallel
assert-dnsdist-running: check-dnsdist-systemd check-dnsdist-doh-listener dnsdist-validate
	@test -z "$(VERBOSE)" || echo "✅ dnsdist service and listener OK"
