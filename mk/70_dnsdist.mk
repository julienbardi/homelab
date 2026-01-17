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
		dnsdist-restart dnsdist-status dnsdist-systemd-dropin \
		install-kdig

install-kdig:
	@$(call apt_install,kdig,dnsutils)

# --------------------------------------------------------------------
# High-level target
# --------------------------------------------------------------------
dnsdist: harden-groups install-kdig \
		dnsdist-install dnsdist-systemd-dropin deploy-dnsdist-certs \
		dnsdist-config dnsdist-validate dnsdist-enable dnsdist-restart
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
dnsdist-config:
	@echo "📄 [make] Deploying dnsdist.conf → $(DNSDIST_CONF_DST)"
	@$(run_as_root) install -d -m 0750 -o root -g _dnsdist /etc/dnsdist
	@$(run_as_root) install -m 0644 -o root -g root \
		$(DNSDIST_CONF_SRC) $(DNSDIST_CONF_DST)

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
# Restart dnsdist cleanly
# --------------------------------------------------------------------
dnsdist-restart:
	@echo "🔄 dnsdist restart requested"
	@$(run_as_root) systemctl restart $(DNSDIST_UNIT)

# --------------------------------------------------------------------
# Status helper
# --------------------------------------------------------------------
dnsdist-status:
	@$(run_as_root) systemctl status $(DNSDIST_UNIT) --no-pager || true

dnsdist-systemd-dropin:
	@echo "⚙️ [make] Installing dnsdist systemd drop-in"
	@$(run_as_root) install -d /etc/systemd/system/dnsdist.service.d
	@$(run_as_root) install -m 0644 \
		$(HOMELAB_DIR)/scripts/systemd/dnsdist.service.d/10-no-port53.conf \
		/etc/systemd/system/dnsdist.service.d/10-no-port53.conf
	@$(run_as_root) systemctl daemon-reload

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

