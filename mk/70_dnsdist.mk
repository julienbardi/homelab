# ============================================================
# mk/70_dnsdist.mk — dnsdist orchestration (DNS over HTTPS)
# ============================================================

# ============================================================
# dnsdist Listener Contract (Proxmox VE Environment)
# ============================================================
#
# dnsdist runs as the primary DoH and selective forwarding frontend,
# serving local loopback clients, WireGuard interfaces, and
# Tailscale/Headscale tunnel endpoints.
#
# dnsdist is responsible for:
#   ✅ IPv6 plain DNS on loopback ([::1]:53)
#   ✅ IPv4 loopback DoH (127.0.0.1:8053)
#   ✅ IPv6 loopback DoH ([::1]:8053)
#   ✅ Plain DNS and DoH bindings across WireGuard gateway interfaces
#   ✅ Integration endpoints for Tailscale/Headscale routing peers
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
# Any validation logic MUST enforce the above loopback requirements
# and support active VPN tunnel gateway listeners.
# ============================================================

# Configuration Destinations & Templates
DNSDIST_CONF_TEMPLATE   := $(REPO_ROOT)/config/dnsdist/dnsdist.conf.template
DNSDIST_CONF_DST        := /etc/dnsdist/dnsdist.conf

ifndef DOMAIN
$(error DOMAIN is not set; export DOMAIN or define it in config.mk)
endif

ifndef CERTS_DEPLOY
$(error CERTS_DEPLOY is not set; expected from mk/config.mk)
endif

# Paths & Binaries
DNSDIST_BIN        := /usr/bin/dnsdist
DNSDIST_UNIT       := dnsdist.service

# Discovery with Override
KDIG               ?= kdig

# Configuration (Ensuring trailing slash safety)
DNSDIST_DROPIN_SRC      := $(REPO_ROOT)/config/systemd/dnsdist.service.d/10-no-port53.conf
DNSDIST_DROPIN_DST      := /etc/systemd/system/dnsdist.service.d/10-no-port53.conf
DNSDIST_CAPS_DROPIN_SRC := $(REPO_ROOT)/config/systemd/dnsdist.service.d/20-homelab-bindcaps.conf
DNSDIST_CAPS_DROPIN_DST := /etc/systemd/system/dnsdist.service.d/20-homelab-bindcaps.conf

# TLS Material
DNSDIST_CERT_DIR    := /etc/dnsdist/certs
DNSDIST_CERT        := $(DNSDIST_CERT_DIR)/fullchain.pem
DNSDIST_KEY         := $(DNSDIST_CERT_DIR)/privkey.pem
CA_BUNDLE          ?= /var/lib/ssl/canonical/fullchain_ecc.pem

# DoH probe defaults (centralized)
DOH_HOST            ?= $(DOMAIN)
DOH_PORT            := 8053
DOH_ADDR            := 127.0.0.1
DOH_TEST_NAME       ?= $(DOMAIN)
DOH_TIMEOUT         := 5
DOH_TLS_CA          := $(CA_BUNDLE)
DOH_TLS_HOST        := $(DOH_HOST)
KDIG_ARGS           := +https +tls-ca=$(DOH_TLS_CA) +tls-hostname=$(DOH_TLS_HOST) +time=$(DOH_TIMEOUT)
CURL_RESOLVE        := --resolve $(DOH_HOST):$(DOH_PORT):$(DOH_ADDR)

# Additional Environment Bindings for Template Rendering
DNSDIST_LAN_IP    ?= 10.89.12.4
DNSDIST_ULA_IP    ?= fd89:7a3b:42c0::4
UNBOUND_PORT      ?= 15335
LAN_SUBNET        ?= 10.89.12.0/24
ULA_PREFIX        ?= fd89:7a3b:42c0::/48

# Commands
DNSDIST_RESTART_CMD := $(run_as_root) systemctl restart $(DNSDIST_UNIT)

# ====================================================================
# Corrected deploy-dnsdist-certs (No circular dependency)
# ====================================================================
deploy-dnsdist-certs: install-all $(CERTS_DEPLOY) $(CANONICAL_SUM)

define dnsdist_render_and_install_config
	$(run_as_root) install -d -m 0750 -o root -g _dnsdist /etc/dnsdist; \
	tmp=$$($(run_as_root) mktemp -p /run homelab.dnsdist.conf.XXXXXX); \
	$(run_as_root) chmod 644 "$$tmp"; \
	export DNSDIST_CERT="$(DNSDIST_CERT)" \
			DNSDIST_KEY="$(DNSDIST_KEY)" \
			DNSDIST_LAN_IP="$(DNSDIST_LAN_IP)" \
			DNSDIST_ULA_IP="$(DNSDIST_ULA_IP)" \
			UNBOUND_PORT="$(UNBOUND_PORT)" \
			DOH_PORT="$(DOH_PORT)" \
			LAN_SUBNET="$(LAN_SUBNET)" \
			ULA_PREFIX="$(ULA_PREFIX)"; \
	$(run_as_root) sh -c ' \
		for v in DNSDIST_CERT DNSDIST_KEY DNSDIST_LAN_IP DNSDIST_ULA_IP UNBOUND_PORT DOH_PORT LAN_SUBNET ULA_PREFIX; do \
			eval "val=\$$$v"; \
			if [ -z "$$val" ]; then \
				echo "❌ Error: Environment variable '\''$$v'\'' is empty or undefined." >&2; \
				exit 1; \
			fi; \
		done; \
		envsubst < "$(DNSDIST_CONF_TEMPLATE)" > "$$0" \
	' "$$tmp"; \
	rc=$$?; \
	if [ "$$rc" -ne 0 ]; then \
		$(run_as_root) rm -f "$$tmp"; \
		exit 1; \
	fi; \
	rc=0; \
	$(run_as_root) env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(INSTALL_FILE_IF_CHANGED) -q \
		"" "" "$$tmp" \
		"" "" "$(DNSDIST_CONF_DST)" \
		"$(ROOT_UID)" "$(ROOT_GID)" "0644" || rc=$$?; \
	$(run_as_root) rm -f "$$tmp"; \
	if [ "$$rc" -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		echo "🔄 dnsdist.conf updated (from template), restarting dnsdist..."; \
		$(DNSDIST_RESTART_CMD); \
	fi
endef

dnsdist-config: dnsdist-install
	@$(call dnsdist_render_and_install_config)

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

dnsdist-systemd-dropin: dnsdist-install
	@$(call dnsdist_install_dropin,$(DNSDIST_DROPIN_SRC),$(DNSDIST_DROPIN_DST))

dnsdist-systemd-caps: dnsdist-systemd-dropin
	@$(call dnsdist_install_dropin,$(DNSDIST_CAPS_DROPIN_SRC),$(DNSDIST_CAPS_DROPIN_DST))

# canonical store and stamp
CANONICAL_DIR := /var/lib/ssl/canonical
CANONICAL_SUM := $(CANONICAL_DIR)/.lastsum

.PHONY: deploy-dnsdist-certs

deploy-dnsdist-certs: install-all $(CERTS_DEPLOY) $(CANONICAL_SUM)

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
		if [ -r "$(DNSDIST_CERT)" ] && [ -r "$(DNSDIST_KEY)" ]; then \
			echo "🔁 canonical store unchanged; skipping deploy"; \
		else \
			echo "📦 canonical unchanged but dnsdist certs missing; forcing deploy"; \
			$(run_as_root) sh -c "exec 9>/var/lock/homelab-deploy.lock; flock -x 9; SSL_CANONICAL_DIR=\"$(SSL_CANONICAL_DIR)\" $(CERTS_DEPLOY) deploy dnsdist"; \
			tmp=$$($(run_as_root) mktemp -p /run homelab.dnsdist.tmp.XXXXXX); \
			$(run_as_root) sh -c 'printf "%s\n" "$$1" > "$$2"' sh "$$sum" "$$tmp"; \
			$(run_as_root) mv "$$tmp" "$(CANONICAL_SUM)"; \
			echo "✅ deploy-dnsdist-certs complete"; \
		fi; \
	else \
		echo "📦 Deploying certificates to dnsdist"; \
		$(run_as_root) sh -c "exec 9>/var/lock/homelab-deploy.lock; flock -x 9; SSL_CANONICAL_DIR=\"$(SSL_CANONICAL_DIR)\" $(CERTS_DEPLOY) deploy dnsdist"; \
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
# Orchestration umbrella (Acyclic Sequential Extension)
# --------------------------------------------------------------------

# Extend existing targets sequentially without creating cycles
dnsdist-systemd-dropin: dnsdist-install
dnsdist-systemd-caps: dnsdist-systemd-dropin
dnsdist-config: dnsdist-systemd-caps deploy-dnsdist-certs
dnsdist-validate: dnsdist-config
dnsdist-enable: dnsdist-validate
assert-dnsdist-running: dnsdist-enable dnsdist-config
check-dnsdist-doh-local: assert-dnsdist-running
install-kdig: check-dnsdist-doh-local
check-dnsdist-listeners: install-kdig

# Master umbrella depends on the final verification and setup leaves
dnsdist: check-dnsdist-listeners
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

# ------------------------------------------------------------
# dnsdist package management
# ------------------------------------------------------------

STAMP_DNSDIST := $(STAMP_DIR_ROOT)/dnsdist.stamp

.PHONY: install-pkg-dnsdist remove-pkg-dnsdist verify-pkg-dnsdist dnsdist-install
install-pkg-dnsdist: ensure-state-dirs
	@set -euo pipefail; \
	if [ -f "$(STAMP_DNSDIST)" ] && [ ! -L "$(STAMP_DNSDIST)" ] && dpkg -s dnsdist >/dev/null 2>&1; then \
		_INST_VER="$$(dpkg-query -W -f='$${Version}' dnsdist 2>/dev/null || echo "")"; \
		_S_VER="$$(grep '^version=' "$(STAMP_DNSDIST)" 2>/dev/null | cut -d= -f2- || echo "")"; \
		if [ -n "$$_INST_VER" ] && [ "$$_S_VER" = "$$_INST_VER" ]; then \
			echo "⏩ dnsdist unchanged (fast-path OK)"; \
			exit 0; \
		fi; \
	fi; \
	echo "📦 Installing dnsdist package..."; \
	$(run_as_root) env DEBIAN_FRONTEND=noninteractive \
		apt-get -o Dpkg::Options::="--force-confdef" \
				-o Dpkg::Options::="--force-confold" \
				install -y dnsdist || { echo "❌ dnsdist installation failed"; exit 1; }; \
	$(run_as_root) mkdir -p "$$(dirname "$(STAMP_DNSDIST)")"; \
	_INST_VER="$$(dpkg-query -W -f='$${Version}' dnsdist 2>/dev/null || echo "unknown")"; \
	{ \
		echo "version=$$_INST_VER"; \
		echo "sha256=$$(dpkg -L dnsdist 2>/dev/null | xargs sha256sum 2>/dev/null | awk '{print $$1}' | sha256sum | awk '{print $$1}' || echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")"; \
		echo "owner=root"; \
		echo "group=root"; \
		echo "perm=0755"; \
		echo "type=package"; \
	} | $(run_as_root) tee "$(STAMP_DNSDIST)" >/dev/null; \
	echo "✅ dnsdist installed"

remove-pkg-dnsdist:
	@$(run_as_root) sh -c ' \
		apt-get purge -y dnsdist >/dev/null 2>&1 || true; \
		apt-get autoremove -y >/dev/null 2>&1 || true; \
		rm -f "$(STAMP_DNSDIST)"; \
	'; \
	echo "🗑️ dnsdist removed"

verify-pkg-dnsdist:
	@if ! dpkg -s dnsdist >/dev/null 2>&1; then \
		echo "❌ dnsdist is not installed"; \
		exit 1; \
	fi; \
	echo "✅ dnsdist package verified"

dnsdist-install: install-pkg-dnsdist verify-pkg-dnsdist