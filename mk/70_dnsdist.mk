# ============================================================
# mk/70_dnsdist.mk — dnsdist orchestration (DNS over HTTPS)
# ============================================================

# ============================================================
# dnsdist Listener Contract (Ugreen NAS running Proxmox)
# ============================================================
#
# UGOS ships dnsmasq bound to IPv4 port 53 on:
#   - 0.0.0.0:53
#   - 127.0.0.1:53
#
# This binding is mandatory and cannot be disabled or restricted.
# Therefore:
#
#   ❌ dnsdist MUST NOT bind 127.0.0.1:53 (UDP or TCP)
#   ❌ dnsdist MUST NOT bind 0.0.0.0:53
#
# dnsdist is responsible for:
#   ✅ IPv6 plain DNS on loopback (::1:53)
#   ✅ IPv6 plain DNS on all WireGuard gateway addresses
#       fd89:7a3b:42c0:N::1:53  (N = 0..15)
#
#   ✅ DoH on IPv4 loopback (127.0.0.1:8053)
#   ✅ DoH on IPv6 loopback ([::1]:8053)
#   ✅ DoH on all WireGuard IPv4/IPv6 gateway addresses
#
# Required listeners for dnsdist:
#
#   Plain DNS (IPv6 only):
#       udp [::1]:53
#       tcp [::1]:53
#
#   DoH (loopback):
#       tcp 127.0.0.1:8053
#       tcp [::1]:8053
#
# WireGuard listeners are validated indirectly via:
#   - presence of fd89:7a3b:42c0:N::1:53 (UDP/TCP)
#   - presence of fd89:7a3b:42c0:N::1:8053 (TCP)
#
# Any validation logic MUST enforce only the above.
# Any check for 127.0.0.1:53 MUST be removed.
#
# ============================================================

# mk/70_dnsdist.mk

ifndef DOMAIN
$(error DOMAIN is not set; export DOMAIN or define it in config.mk)
endif

ifndef CERTS_DEPLOY
$(error CERTS_DEPLOY is not set; expected from mk/config.mk)
endif

# Paths & Binaries
DNSDIST_BIN          := /usr/bin/dnsdist
DNSDIST_UNIT         := dnsdist.service

# Discovery with Override
KDIG                 ?= kdig

# Configuration (Ensuring trailing slash safety)
DNSDIST_CONF_SRC        := $(REPO_ROOT)/config/dnsdist/dnsdist.conf
DNSDIST_CONF_DST        := /etc/dnsdist/dnsdist.conf
DNSDIST_DROPIN_SRC      := $(REPO_ROOT)/config/systemd/dnsdist.service.d/10-no-port53.conf
DNSDIST_DROPIN_DST      := /etc/systemd/system/dnsdist.service.d/10-no-port53.conf
DNSDIST_CAPS_DROPIN_SRC := $(REPO_ROOT)/config/systemd/dnsdist.service.d/20-homelab-bindcaps.conf
DNSDIST_CAPS_DROPIN_DST := /etc/systemd/system/dnsdist.service.d/20-homelab-bindcaps.conf

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

define dnsdist_install_dropin
	@$(run_as_root) install -d /etc/systemd/system/dnsdist.service.d; \
	rc=0; \
	$(run_as_root) env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(INSTALL_FILE_IF_CHANGED) -q \
		"" "" "$(1)" \
		"" "" "$(2)" \
		"$(ROOT_UID)" "$(ROOT_GID)" "0644" || rc=$$?; \
	if [ "$$rc" -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		$(systemctl_daemon_reload); \
		echo "🔄 Updated $(2), restarting dnsdist..."; \
		$(DNSDIST_RESTART_CMD); \
	fi
endef

.PHONY: \
	dnsdist \
	dnsdist-install dnsdist-config dnsdist-enable dnsdist-validate \
	dnsdist-status dnsdist-systemd-dropin \
	deploy-dnsdist-certs install-kdig \
	assert-dnsdist-certs assert-dnsdist-running \
	check-dnsdist-doh-local check-dnsdist-doh-listener check-dnsdist-systemd \
	dnsdist-pre-reboot-check check-dnsdist-listeners

# --------------------------------------------------------------------
# Dependencies & Setup
# --------------------------------------------------------------------
assert-dnsdist-certs:
	@$(run_as_root) sh -eu -c 'for f in "$(DNSDIST_CERT)" "$(DNSDIST_KEY)"; do \
		[ -r "$$f" ] || { echo "❌ Missing/unreadable: $$f"; exit 1; }; \
	done'
	@echo "✅ TLS material present"

# --------------------------------------------------------------------
# Implementation Details (Idempotent)
# --------------------------------------------------------------------

dnsdist-config: dnsdist-install
	@$(run_as_root) install -d -m 0750 -o root -g _dnsdist /etc/dnsdist; \
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

dnsdist-systemd-dropin:
	@$(call dnsdist_install_dropin,$(DNSDIST_DROPIN_SRC),$(DNSDIST_DROPIN_DST))

dnsdist-systemd-caps:
	@$(call dnsdist_install_dropin,$(DNSDIST_CAPS_DROPIN_SRC),$(DNSDIST_CAPS_DROPIN_DST))

# canonical store and stamp
CANONICAL_DIR := /var/lib/ssl/canonical
CANONICAL_SUM := $(CANONICAL_DIR)/.lastsum

.PHONY: deploy-dnsdist-certs

# deploy depends on the stamp so deploy runs only when canonical store changed
deploy-dnsdist-certs: install-all $(CERTS_DEPLOY) $(CANONICAL_SUM) dnsdist-config

# Robust checksum + deploy (atomic stamp write)
$(CANONICAL_SUM): $(CERTS_DEPLOY)
	@set -eu; \
	if [ ! -d "$(CANONICAL_DIR)" ]; then \
	echo "⚠️  canonical dir missing: $(CANONICAL_DIR)"; exit 1; \
	fi; \
	if ! command -v sha256sum >/dev/null 2>&1; then \
	echo "❌ sha256sum not found"; exit 1; \
	fi; \
	nfiles=$$($(run_as_root) find "$(CANONICAL_DIR)" -type f -print -quit | wc -l); \
	if [ "$$nfiles" -eq 0 ]; then \
		echo "⚠️  canonical store empty: $(CANONICAL_DIR)"; \
		tmp=$$($(run_as_root) mktemp -p /run homelab.dnsdist.tmp.XXXXXX); \
		$(run_as_root) sh -c 'printf "%s\n" "" > "$$1"' sh "$$tmp"; \
		$(run_as_root) mv "$$tmp" "$(CANONICAL_SUM)"; \
		exit 0; \
	fi; \
	sum=$$($(run_as_root) sh -c "find '$(CANONICAL_DIR)' -type f -exec sha256sum {} + 2>/dev/null | sort | sha256sum | cut -d' ' -f1"); \
	old=""; [ -f "$(CANONICAL_SUM)" ] && old=$$($(run_as_root) cat "$(CANONICAL_SUM)" 2>/dev/null || true); \
	if [ "$$sum" = "$$old" ]; then \
		# canonical store unchanged: only skip if dnsdist certs are actually present \
		if [ -r "$(DNSDIST_CERT)" ] && [ -r "$(DNSDIST_KEY)" ]; then \
			echo "🔁 canonical store unchanged; skipping deploy"; \
		else \
			echo "📦 canonical unchanged but dnsdist certs missing; forcing deploy"; \
			$(run_as_root) sh -c "exec 9>/var/lock/homelab-deploy.lock; flock -x 9; $(CERTS_DEPLOY) deploy dnsdist"; \
			tmp=$$($(run_as_root) mktemp -p /run homelab.dnsdist.tmp.XXXXXX); \
			$(run_as_root) sh -c 'printf "%s\n" "$$1" > "$$2"' sh "$$sum" "$$tmp"; \
			$(run_as_root) mv "$$tmp" "$(CANONICAL_SUM)"; \
			echo "✅ deploy-dnsdist-certs complete"; \
		fi; \
	else \
		echo "📦 Deploying certificates to dnsdist"; \
		$(run_as_root) sh -c "exec 9>/var/lock/homelab-deploy.lock; flock -x 9; $(CERTS_DEPLOY) deploy dnsdist"; \
		tmp=$$($(run_as_root) mktemp -p /run homelab.dnsdist.tmp.XXXXXX); \
		$(run_as_root) sh -c 'printf "%s\n" "$$1" > "$$2"' sh "$$sum" "$$tmp"; \
		$(run_as_root) mv "$$tmp" "$(CANONICAL_SUM)"; \
		echo "✅ deploy-dnsdist-certs complete"; \
	fi

# --------------------------------------------------------------------
# Verification & Status
# --------------------------------------------------------------------
dnsdist-validate: deploy-dnsdist-certs
	@echo "🔍 Validating dnsdist configuration"
	@$(run_as_root) $(DNSDIST_BIN) --check-config

dnsdist-enable: deploy-dnsdist-certs
	@echo "⚙️  Enabling dnsdist service"
	@$(run_as_root) systemctl enable $(DNSDIST_UNIT)

check-dnsdist-doh-local:
	@[ -r "$(DOH_TLS_CA)" ] || { echo "❌ Missing CA bundle: $(DOH_TLS_CA)"; exit 1; }; \
	KDIG_BIN=$$(command -v $(KDIG) || true); \
	if [ -n "$$KDIG_BIN" ]; then \
		if $(run_as_root) $$KDIG_BIN @$(DOH_ADDR) -p $(DOH_PORT) $(DOH_TEST_NAME) $(KDIG_ARGS) >/dev/null 2>&1; then \
			echo "✅ DoH resolution successful (kdig)"; \
		else \
			echo "❌ DoH resolution failed (kdig). Diagnostic:"; \
			$(run_as_root) $$KDIG_BIN @$(DOH_ADDR) -p $(DOH_PORT) $(DOH_TEST_NAME) $(KDIG_ARGS); \
			exit 1; \
		fi; \
	else \
		echo "⚠️  kdig not found — using curl fallback"; \
		if curl -s -o /dev/null --fail \
			$(CURL_RESOLVE) \
			--http2 \
			--cacert "$(DOH_TLS_CA)" \
			-H 'accept: application/dns-message' \
			"https://$(DOH_HOST):$(DOH_PORT)/dns-query?dns=AAABAAABAAAAAAAAB2V4YW1wbGUDY29tAAABAAE"; then \
			echo "✅ DoH endpoint reachable (curl fallback)"; \
		else \
			echo "❌ DoH endpoint unreachable (curl fallback)"; \
			exit 1; \
		fi; \
	fi


# --------------------------------------------------------------------
# Orchestration umbrella
# --------------------------------------------------------------------

dnsdist: dnsdist-install dnsdist-systemd-dropin dnsdist-systemd-caps deploy-dnsdist-certs \
	dnsdist-config dnsdist-enable dnsdist-validate \
	assert-dnsdist-running check-dnsdist-doh-listener check-dnsdist-doh-local \
	install-kdig check-dnsdist-listeners
	@test -z "$(VERBOSE)" || echo "🚀 dnsdist DoH frontend ready"

ci-doh-check:
	@RAND=$$(date +%s); \
	TEST="probe-$$RAND.$(DOMAIN)"; \
	KDIG_BIN=$$(command -v $(KDIG) || true); \
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

check-dnsdist-systemd:
	@if ! $(run_as_root) systemctl is-active --quiet $(DNSDIST_UNIT); then \
		echo "❌ $(DNSDIST_UNIT) is not active"; \
		$(run_as_root) systemctl --no-pager status $(DNSDIST_UNIT) || true; \
		exit 1; \
	fi; \
	echo "✅ $(DNSDIST_UNIT) active"

check-dnsdist-doh-listener:
	@if ! $(run_as_root) ss -ltn "sport = :$(DOH_PORT)" | grep -q LISTEN; then \
		echo "❌ DoH listener not present on :$(DOH_PORT)"; \
		$(run_as_root) ss -ltn | sed -n '1,120p' || true; \
		exit 1; \
	fi; \
	echo "✅ DoH listener present on :$(DOH_PORT)"

# assert depends on both checks; with `make -j` they can run in parallel
assert-dnsdist-running: check-dnsdist-systemd check-dnsdist-doh-listener dnsdist-validate
	@test -z "$(VERBOSE)" || echo "✅ dnsdist service and listener OK"

dnsdist-pre-reboot-check:
	@echo "🔍 Validating dnsdist before reboot"
	@$(run_as_root) $(DNSDIST_BIN) --check-config
	@$(run_as_root) ss -lnt | grep -q ":$(DOH_PORT)" \
		|| { echo "❌ dnsdist not listening on :$(DOH_PORT)"; exit 1; }
	@echo "✅ dnsdist healthy"

check-dnsdist-listeners: $(INSTALL_PATH)/dnsdist-validate-listeners.sh
	@echo "🔍 Checking dnsdist listeners"
	@$(run_as_root) $(INSTALL_PATH)/dnsdist-validate-listeners.sh
