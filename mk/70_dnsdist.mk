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
		dnsdist-restart dnsdist-status dnsdist-systemd-dropin

# --------------------------------------------------------------------
# High-level target
# --------------------------------------------------------------------
dnsdist: install-kdig \
		dnsdist-install dnsdist-systemd-dropin deploy-dnsdist-certs \
		dnsdist-config dnsdist-validate dnsdist-enable dnsdist-restart
	@echo "🚀 [make] dnsdist DoH frontend ready"

# --------------------------------------------------------------------
# Install dnsdist (Debian package)
# --------------------------------------------------------------------
dnsdist-install:
	@if command -v $(DNSDIST_BIN) >/dev/null; then \
		echo "[make] dnsdist binary present"; \
	else \
		echo "[make] Installing dnsdist"; \
		sudo apt-get update; \
		sudo apt-get install -y dnsdist; \
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
	@sudo install -d -m 0750 -o root -g _dnsdist /etc/dnsdist
	@sudo install -m 0644 -o root -g root \
		$(DNSDIST_CONF_SRC) $(DNSDIST_CONF_DST)

# --------------------------------------------------------------------
# Validate dnsdist configuration (no daemon)
# --------------------------------------------------------------------
dnsdist-validate:
	@echo "🔍 [make] Validating dnsdist configuration"
	@sudo $(DNSDIST_BIN) --check-config

# --------------------------------------------------------------------
# Enable dnsdist service (no start yet)
# --------------------------------------------------------------------
dnsdist-enable:
	@echo "⚙️ [make] Enabling dnsdist service"
	@sudo systemctl enable $(DNSDIST_UNIT)

# --------------------------------------------------------------------
# Restart dnsdist cleanly
# --------------------------------------------------------------------
dnsdist-restart:
	@echo "🔄 [make] Restarting dnsdist"
	@sudo systemctl restart $(DNSDIST_UNIT)

# --------------------------------------------------------------------
# Status helper
# --------------------------------------------------------------------
dnsdist-status:
	@sudo systemctl status $(DNSDIST_UNIT) --no-pager || true

dnsdist-systemd-dropin:
	@echo "⚙️ [make] Installing dnsdist systemd drop-in"
	@sudo install -d /etc/systemd/system/dnsdist.service.d
	@sudo install -m 0644 \
		$(HOMELAB_DIR)/scripts/systemd/dnsdist.service.d/10-no-port53.conf \
		/etc/systemd/system/dnsdist.service.d/10-no-port53.conf
	@sudo systemctl daemon-reload