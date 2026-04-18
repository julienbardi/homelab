# ============================================================
# mk/70_dnsdist.mk — dnsdist orchestration (DNS over HTTPS)
# ============================================================

DEPLOY_CERTS        := $(INSTALL_PATH)/deploy_certificates.sh

DNSDIST_BIN         := /usr/bin/dnsdist
DNSDIST_UNIT        := dnsdist.service

DNSDIST_CONF_SRC    := $(REPO_ROOT)config/dnsdist/dnsdist.conf
DNSDIST_CONF_DST    := /etc/dnsdist/dnsdist.conf

DNSDIST_CERT_DIR    := /etc/dnsdist/certs
DNSDIST_CERT        := $(DNSDIST_CERT_DIR)/fullchain.pem
DNSDIST_KEY         := $(DNSDIST_CERT_DIR)/privkey.pem

DNSDIST_RESTART_CMD := $(run_as_root) systemctl restart $(DNSDIST_UNIT)

.PHONY: \
	dnsdist dnsdist-bootstrap dnsdist-runtime dnsdist-verify \
	dnsdist-install dnsdist-config dnsdist-enable dnsdist-validate \
	dnsdist-status dnsdist-systemd-dropin \
	deploy-dnsdist-certs install-kdig \
	assert-dnsdist-certs assert-dnsdist-running \
	check-dnsdist-doh-local check-dnsdist-doh-listener

.NOTPARALLEL: dnsdist dnsdist-config dnsdist-systemd-dropin \
			  deploy-dnsdist-certs dnsdist-install dnsdist-enable

# --------------------------------------------------------------------
# Dependencies & Setup
# --------------------------------------------------------------------

install-kdig:
	@$(call apt_install,kdig,dnsutils)

assert-dnsdist-certs:
	@echo "🔍 Checking dnsdist TLS material..."
	@$(run_as_root) sh -eu -c 'for f in "$(DNSDIST_CERT)" "$(DNSDIST_KEY)"; do \
		[ -r "$$f" ] || { echo "❌ Missing/unreadable: $$f"; exit 1; }; \
	done'
	@echo "✅ TLS material present"

# --------------------------------------------------------------------
# Orchestration Targets
# --------------------------------------------------------------------

dnsdist-bootstrap: \
	dnsdist-install \
	dnsdist-systemd-dropin

dnsdist-runtime: \
	install-kdig \
	deploy-dnsdist-certs \
	assert-dnsdist-certs \
	dnsdist-config \
	dnsdist-enable

dnsdist: \
	harden-groups \
	dnsdist-bootstrap \
	dnsdist-runtime \
	dnsdist-verify
	@echo "🚀 dnsdist DoH frontend ready"

# --------------------------------------------------------------------
# Implementation Details (Keyword-Free / Idempotent)
# --------------------------------------------------------------------

dnsdist-install:
	@command -v $(DNSDIST_BIN) >/dev/null && echo "🔄 dnsdist binary already present" || { \
		echo "Installing dnsdist..."; \
		$(call apt_update_if_needed); \
		$(call apt_install,dnsdist,dnsdist); \
	}

dnsdist-config:
	@set -eu; \
	$(run_as_root) install -d -m 0750 -o root -g _dnsdist /etc/dnsdist; \
	rc=0; \
	$(run_as_root) env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(INSTALL_FILE_IF_CHANGED) -q \
		"" "" "$(DNSDIST_CONF_SRC)" \
		"" "" "$(DNSDIST_CONF_DST)" \
		"root" "root" "0644" || rc=$$?; \
	[ "$$rc" -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ] && { \
		echo "🔄 dnsdist.conf updated, restarting service..."; \
		$(DNSDIST_RESTART_CMD); \
	} || { [ "$$rc" -eq 0 ] || exit "$$rc"; }

dnsdist-systemd-dropin: ensure-run-as-root
	@set -eu; \
	echo "⚙️  Installing dnsdist systemd drop-in"; \
	$(run_as_root) install -d /etc/systemd/system/dnsdist.service.d; \
	rc=0; \
	$(run_as_root) env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(INSTALL_FILE_IF_CHANGED) -q \
		"" "" "$(REPO_ROOT)scripts/systemd/dnsdist.service.d/10-no-port53.conf" \
		"" "" "/etc/systemd/system/dnsdist.service.d/10-no-port53.conf" \
		"root" "root" "0644" || rc=$$?; \
	$(run_as_root) systemctl daemon-reload; \
	[ "$$rc" -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ] && { \
		echo "🔄 dnsdist drop-in updated, restarting service..."; \
		$(DNSDIST_RESTART_CMD); \
	} || { [ "$$rc" -eq 0 ] || exit "$$rc"; }

deploy-dnsdist-certs: acme-renew-all install-all $(HOMELAB_ENV_DST) $(DEPLOY_CERTS)
	@echo "📦 Deploying certificates to dnsdist"
	@$(run_as_root) $(DEPLOY_CERTS) deploy dnsdist

# --------------------------------------------------------------------
# Verification & Status
# --------------------------------------------------------------------

dnsdist-validate:
	@echo "🔍 Validating dnsdist configuration"
	@$(run_as_root) $(DNSDIST_BIN) --check-config

dnsdist-enable:
	@echo "⚙️  Enabling dnsdist service"
	@$(run_as_root) systemctl enable $(DNSDIST_UNIT)

dnsdist-status:
	@$(run_as_root) systemctl status $(DNSDIST_UNIT) --no-pager || true

assert-dnsdist-running:
	@systemctl is-active --quiet dnsdist && echo "✅ dnsdist service active" || \
		{ echo "❌ dnsdist service NOT active"; exit 1; }

check-dnsdist-doh-listener:
	@ss -ltn sport = :8053 | grep -q LISTEN && echo "✅ dnsdist DoH listener active on port 8053" || \
		{ echo "❌ dnsdist DoH listener NOT active on port 8053"; exit 1; }

# mk/70_dnsdist.mk

check-dnsdist-doh-local:
	@echo "🧪 Testing local DoH resolution..."
	@# Use the standard DoH wireformat (RFC 8484): send a base64url DNS wire query as the dns= parameter.
	@# Keep -k to mirror bootstrap behaviour that tolerates local CA issues; remove later when CA chain is trusted.
	@DOH_DNS=$$(python3 -c "import base64; hdr=b'\x1a\x2b\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00'; qname=b'\x06google\x03com\x00'; qtail=b'\x00\x01\x00\x01'; q=hdr+qname+qtail; print(base64.urlsafe_b64encode(q).rstrip(b'=').decode())"); \
	if ! $(run_as_root) curl -sS -k --http2 "https://127.0.0.1:8053/dns-query?dns=$$DOH_DNS" --output - >/dev/null 2>&1; then \
		echo "❌ FATAL: DoH resolution failed even with -k."; \
		exit 1; \
	fi
	@echo "✅ DoH resolution successful (verified via local override)"

dnsdist-verify: \
	dnsdist-validate \
	assert-dnsdist-running \
	check-dnsdist-doh-listener \
	check-dnsdist-doh-local
	@echo "🎉 dnsdist verification complete"