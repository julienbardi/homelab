# mk/70_dnscrypt-proxy.mk
# Idempotent Makefile fragment to install and configure dnscrypt-proxy.
# Replaces CoreDNS orchestration.

.ONESHELL:
SHELL := /bin/bash

DNSCRYPT_BIN := /usr/bin/dnscrypt-proxy
DNSCRYPT_CONF_SRC := $(HOMELAB_DIR)/config/dnscrypt-proxy/dnscrypt-proxy.toml
DNSCRYPT_CONF_DEST := /etc/dnscrypt-proxy/dnscrypt-proxy.toml

RUN_USER ?= dnscrypt
SERVICE_NAME ?= dnscrypt-proxy
SYSTEMD_UNIT := /etc/systemd/system/$(SERVICE_NAME).service
OVERWRITE_UNIT ?= 0

.PHONY: install-pkg-dnscrypt-proxy

install-pkg-dnscrypt-proxy:
	@echo "🛠️ Installing and configuring dnscrypt-proxy..."
	set -euo pipefail

	# refresh package index
	sudo apt-get update

	# install or upgrade only dnscrypt-proxy
	if ! command -v $(DNSCRYPT_BIN) >/dev/null 2>&1; then \
		echo "📥 Installing dnscrypt-proxy"; \
		sudo apt-get install --no-install-recommends -y dnscrypt-proxy; \
	else \
		echo "🔄 Upgrading dnscrypt-proxy only"; \
		sudo apt-get install --no-install-recommends --only-upgrade -y dnscrypt-proxy; \
	fi

	# prepare runtime user
	if ! id -u $(RUN_USER) >/dev/null 2>&1; then \
		echo "👤 Creating runtime user $(RUN_USER)"; \
		sudo useradd --system --no-create-home --shell /usr/sbin/nologin $(RUN_USER) || true; \
	fi

	# install curated config
	@echo "📑 Installing dnscrypt-proxy.toml from $(DNSCRYPT_CONF_SRC) -> $(DNSCRYPT_CONF_DEST)"
	sudo install -m 0644 "$(DNSCRYPT_CONF_SRC)" "$(DNSCRYPT_CONF_DEST)"

	# create or overwrite systemd unit
	if [ ! -f "$(SYSTEMD_UNIT)" ] || [ "$(OVERWRITE_UNIT)" = "1" ]; then \
		echo "📝 Writing systemd unit to $(SYSTEMD_UNIT)"; \
		printf '%s\n' \
"[Unit]" \
"Description=dnscrypt-proxy DNS resolver" \
"After=network.target" \
"" \
"[Service]" \
"ExecStart=$(DNSCRYPT_BIN) -config $(DNSCRYPT_CONF_DEST)" \
"User=$(RUN_USER)" \
"Group=$(RUN_USER)" \
"Restart=on-failure" \
"LimitNOFILE=65536" \
"" \
"[Install]" \
"WantedBy=multi-user.target" \
		| sudo tee "$(SYSTEMD_UNIT)" > /dev/null ; \
	else \
		echo "ℹ️ systemd unit exists at $(SYSTEMD_UNIT); set OVERWRITE_UNIT=1 to replace"; \
	fi

	# enable and start service
	@echo "🚀 Enabling and starting dnscrypt-proxy service"
	sudo systemctl daemon-reload
	sudo systemctl enable $(SERVICE_NAME) || true
	if sudo systemctl is-active --quiet $(SERVICE_NAME); then \
		sudo systemctl restart $(SERVICE_NAME) || true; \
	else \
		sudo systemctl start $(SERVICE_NAME) || true; \
	fi

	# verification hints
	$(DNSCRYPT_BIN) -version || echo "⚠️ WARNING: unable to query dnscrypt-proxy version"
	sudo systemctl status $(SERVICE_NAME) --no-pager || true

	@echo "✅ install-pkg-dnscrypt-proxy: done (binary -> $(DNSCRYPT_BIN))"
