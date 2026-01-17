# ============================================================
# mk/70_dnsdist.mk — dnsdist orchestration (DNS over HTTPS)
# ============================================================

DNSDIST_BIN        := /usr/bin/dnsdist
DNSDIST_UNIT       := dnsdist.service

DNSDIST_CONF_SRC   := $(HOMELAB_DIR)/config/dnsdist/dnsdist.conf
DNSDIST_CONF_DST   := /etc/dnsdist/dnsdist.conf

DNSDIST_CERT_DIR   := /etc/dnsdist
DNSDIST_CERT       := $(DNSDIST_CERT_DIR)/fullchain.pem
DNSDIST_KEY        := $(DNSDIST_CERT_DIR)/privkey.pem

.PHONY: dnsdist dnsdist-install deploy-dnsdist-certs \
		dnsdist-config dnsdist-validate dnsdist-enable \
		dnsdist-status dnsdist-systemd-dropin \
		install-kdig

install-kdig:
	@$(call apt_install,kdig,dnsutils)

# --------------------------------------------------------------------
# High-level target
# --------------------------------------------------------------------
dnsdist: harden-groups install-kdig \
		dnsdist-install dnsdist-systemd-dropin deploy-dnsdist-certs \
		dnsdist-config dnsdist-validate dnsdist-enable
	@echo "🚀 dnsdist DoH frontend ready"

# --------------------------------------------------------------------
# Install dnsdist (Debian package)
# --------------------------------------------------------------------
dnsdist-install:
	@if command -v $(DNSDIST_BIN) >/dev/null; then \
		echo "🔁 dnsdist binary already present"; \
	else \
		echo "[make] Installing dnsdist"; \
		$(call apt_update_if_needed); \
		$(call apt_install,dnsdist,dnsdist); \
	fi

# --------------------------------------------------------------------
# Deploy TLS certificates for dnsdist (least privilege)
# --------------------------------------------------------------------
deploy-dnsdist-certs:
	./scripts/setup/deploy_certificates.sh deploy dnsdist

# --------------------------------------------------------------------
# Deploy dnsdist configuration
# --------------------------------------------------------------------
.PHONY: dnsdist-config
dnsdist-config:
	@set -eu; \
	$(run_as_root) install -d -m 0750 -o root -g _dnsdist /etc/dnsdist; \
	CHANGED_EXIT_CODE=3 \
	$(run_as_root) $(HOMELAB_DIR)/scripts/install_if_changed.sh \
		"$(DNSDIST_CONF_SRC)" "$(DNSDIST_CONF_DST)" root root 0644; \
	rc="$$?"; \
	if [ "$$rc" -eq 3 ]; then \
		echo "🔄 dnsdist.conf updated"; \
		echo "🔁 restarting dnsdist.service"; \
		$(run_as_root) systemctl restart $(DNSDIST_UNIT); \
	fi

# --------------------------------------------------------------------
# Validate dnsdist configuration (no daemon)
# --------------------------------------------------------------------
dnsdist-validate:
	@echo "🔍 [make] Validating dnsdist configuration"
	@$(run_as_root) $(DNSDIST_BIN) --check-config

# --------------------------------------------------------------------
# Enable dnsdist service (no start yet)
# --------------------------------------------------------------------
dnsdist-enable:
	@echo "⚙️ [make] Enabling dnsdist service"
	@$(run_as_root) systemctl enable $(DNSDIST_UNIT)

# --------------------------------------------------------------------
# Status helper
# --------------------------------------------------------------------
dnsdist-status:
	@$(run_as_root) systemctl status $(DNSDIST_UNIT) --no-pager || true

dnsdist-systemd-dropin:
	@set -eu; \
	echo "⚙️ [make] Installing dnsdist systemd drop-in"; \
	$(run_as_root) install -d /etc/systemd/system/dnsdist.service.d; \
	CHANGED_EXIT_CODE=3 \
	$(run_as_root) $(HOMELAB_DIR)/scripts/install_if_changed.sh \
		"$(HOMELAB_DIR)/scripts/systemd/dnsdist.service.d/10-no-port53.conf" \
		"/etc/systemd/system/dnsdist.service.d/10-no-port53.conf" \
		root root 0644; \
	rc="$$?"; \
	$(run_as_root) systemctl daemon-reload; \
	if [ "$$rc" -eq 3 ]; then \
		echo "🔄 dnsdist drop-in updated"; \
		echo "🔁 restarting dnsdist.service"; \
		$(run_as_root) systemctl restart $(DNSDIST_UNIT); \
	fi

.PHONY: assert-dnsdist-running
assert-dnsdist-running:
	@systemctl is-active --quiet dnsdist || \
		( echo "❌ dnsdist is not running"; exit 1 )

.PHONY: check-dnsdist-doh-local
check-dnsdist-doh-local:
	@curl -fsS \
		--connect-timeout 2 \
		--max-time 5 \
		-H 'accept: application/dns-message' \
		--data-binary @/dev/null \
		http://127.0.0.1:8053/dns-query >/dev/null || \
		( echo "❌ dnsdist DoH endpoint not responding locally within 5s"; exit 1 )

