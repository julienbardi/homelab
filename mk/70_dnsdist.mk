# ============================================================
# mk/70_dnsdist.mk — dnsdist orchestration (DNS over HTTPS)
# ============================================================

DEPLOY_CERTS := $(INSTALL_PATH)/deploy_certificates.sh
INSTALL_IF_CHANGED := $(INSTALL_PATH)/install_if_changed.sh

DNSDIST_BIN        := /usr/bin/dnsdist
DNSDIST_UNIT       := dnsdist.service

DNSDIST_CONF_SRC   := $(MAKEFILE_DIR)config/dnsdist/dnsdist.conf
DNSDIST_CONF_DST   := /etc/dnsdist/dnsdist.conf

DNSDIST_CERT_DIR := /etc/dnsdist/certs
DNSDIST_CERT       := $(DNSDIST_CERT_DIR)/fullchain.pem
DNSDIST_KEY        := $(DNSDIST_CERT_DIR)/privkey.pem

DNSDIST_RESTART_CMD := $(run_as_root) systemctl restart $(DNSDIST_UNIT)

.PHONY: \
	dnsdist dnsdist-bootstrap dnsdist-runtime dnsdist-verify \
	dnsdist-install dnsdist-config dnsdist-enable dnsdist-validate \
	dnsdist-status dnsdist-systemd-dropin \
	deploy-dnsdist-certs install-kdig \
	assert-dnsdist-certs assert-dnsdist-running \
	check-dnsdist-doh-local

.NOTPARALLEL: dnsdist dnsdist-config dnsdist-systemd-dropin \
	          deploy-dnsdist-certs dnsdist-install dnsdist-enable

install-kdig:
	@$(call apt_install,kdig,dnsutils)

assert-dnsdist-certs:
	@$(run_as_root) sh -eu -c '\
	    for f in "$(DNSDIST_CERT)" "$(DNSDIST_KEY)"; do \
	        if [ ! -r "$$f" ]; then \
	            echo "❌ Missing or unreadable dnsdist TLS file: $$f"; \
	            echo "👉 Ensure certificates have been issued and permissions are correct"; \
	            exit 1; \
	        fi; \
	    done'

dnsdist-bootstrap: \
	dnsdist-install \
	dnsdist-systemd-dropin

dnsdist-runtime: \
	install-kdig \
	deploy-dnsdist-certs \
	assert-dnsdist-certs \
	dnsdist-config \
	dnsdist-enable

# --------------------------------------------------------------------
# Runtime orchestration (safe to re-run)
# --------------------------------------------------------------------
dnsdist: \
	harden-groups \
	dnsdist-bootstrap \
	dnsdist-runtime \
	dnsdist-verify
	@echo "🚀 dnsdist DoH frontend ready"

# --------------------------------------------------------------------
# Bootstrap (one-time, idempotent)
# --------------------------------------------------------------------
dnsdist-install:
	@if command -v $(DNSDIST_BIN) >/dev/null; then \
	    echo "🔁 dnsdist binary already present"; \
	else \
	    echo "Installing dnsdist"; \
	    $(call apt_update_if_needed); \
	    $(call apt_install,dnsdist,dnsdist); \
	fi

# --------------------------------------------------------------------
# Certificate consumption (external authority)
# --------------------------------------------------------------------
# NOTE:
# - dnsdist consumes certificates
# - Certificate lifecycle is owned elsewhere
# - dnsdist must never mutate cert material
deploy-dnsdist-certs: install-all $(HOMELAB_ENV_DST) $(DEPLOY_CERTS)
	$(run_as_root) $(DEPLOY_CERTS) deploy dnsdist

# --------------------------------------------------------------------
# Configuration rendering (idempotent)
# --------------------------------------------------------------------
# --------------------------------------------------------------------
# � ️  Destructive operations (operator-visible)
# --------------------------------------------------------------------
# NOTE:
# - dnsdist restarts interrupt active DNS clients
# - Safe but disruptive
# - Restart behavior is isolated for clarity
dnsdist-config:
	@set -eu; \
	$(run_as_root) install -d -m 0750 -o root -g _dnsdist /etc/dnsdist; \
	rc=0; \
	$(run_as_root) $(INSTALL_IF_CHANGED) \
	    "$(DNSDIST_CONF_SRC)" "$(DNSDIST_CONF_DST)" root root 0644 || rc="$$?"; \
	if [ "$$rc" -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
	    echo "🔄 dnsdist.conf updated"; \
	    echo "🔁 restarting dnsdist.service"; \
	    $(DNSDIST_RESTART_CMD); \
	elif [ "$$rc" -ne 0 ]; then \
	    exit "$$rc"; \
	fi

# --------------------------------------------------------------------
# Verification (post-deploy, read-only)
# --------------------------------------------------------------------
dnsdist-validate:
	@echo "🔍 Validating dnsdist configuration"
	@$(run_as_root) $(DNSDIST_BIN) --check-config

# --------------------------------------------------------------------
# Enable dnsdist service (no start yet)
# --------------------------------------------------------------------
dnsdist-enable:
	@echo "⚙️ Enabling dnsdist service"
	@$(run_as_root) systemctl enable $(DNSDIST_UNIT)

# --------------------------------------------------------------------
# Status helper
# --------------------------------------------------------------------
dnsdist-status:
	@$(run_as_root) systemctl status $(DNSDIST_UNIT) --no-pager || true

# NOTE:
# - The following targets may restart dnsdist
# - Restarts are disruptive to active clients
# - Destructive behavior will be isolated explicitly
dnsdist-systemd-dropin:
	@set -eu; \
	echo "⚙️ Installing dnsdist systemd drop-in"; \
	$(run_as_root) install -d /etc/systemd/system/dnsdist.service.d; \
	$(run_as_root) $(INSTALL_IF_CHANGED) \
	    "$(MAKEFILE_DIR)scripts/systemd/dnsdist.service.d/10-no-port53.conf" \
	    "/etc/systemd/system/dnsdist.service.d/10-no-port53.conf" \
	    root root 0644; \
	rc="$$?"; \
	$(run_as_root) systemctl daemon-reload; \
	if [ "$$rc" -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
	    echo "🔄 dnsdist drop-in updated"; \
	    echo "🔁 restarting dnsdist.service"; \
	    $(DNSDIST_RESTART_CMD); \
	fi

assert-dnsdist-running:
	@systemctl is-active --quiet dnsdist \
	&& echo "✅ dnsdist service active" \
	|| ( echo "❌ dnsdist service NOT active"; exit 1 )

check-dnsdist-doh-listener:
	@ss -ltn sport = :8053 | grep -q LISTEN \
	    && echo "✅ dnsdist DoH listener active on port 8053" \
	    || ( echo "❌ dnsdist DoH listener NOT active on port 8053"; exit 1 )

dnsdist-verify: \
	dnsdist-validate \
	assert-dnsdist-running \
	check-dnsdist-doh-listener
	@echo "🎉 dnsdist verification complete"
