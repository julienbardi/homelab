# 40_code-server.mk
.PHONY: \
	code-server-install \
	code-server-config \
	code-server-systemd \
	code-server-enable \
	code-server

CODE_SERVER_PORT := 8080
CODE_SERVER_USER := $(USER)

CODE_SERVER_CONFIG_SRC := $(MAKEFILE_DIR)config/code-server/config.yaml
CODE_SERVER_CONFIG_DST := $(HOME)/.config/code-server/config.yaml

CODE_SERVER_SYSTEMD_DIR := $(SYSTEMD_DIR)/code-server@.service.d
CODE_SERVER_SYSTEMD_OVERRIDE := $(CODE_SERVER_SYSTEMD_DIR)/override.conf

#
# Install code-server if missing
#
code-server-install:
	@if command -v code-server >/dev/null 2>&1; then \
		echo "[make] code-server already installed"; \
	else \
		echo "[make] Installing code-server"; \
		curl -fsSL https://code-server.dev/install.sh | sh; \
	fi

#
# Deploy user config (authoritative source lives in repo)
#
code-server-config:
	@echo "[make] Deploying code-server config"
	@mkdir -p $(dir $(CODE_SERVER_CONFIG_DST))
	@install -m 600 $(CODE_SERVER_CONFIG_SRC) $(CODE_SERVER_CONFIG_DST)

#
# Install systemd override to pin config path explicitly
#
code-server-systemd:
	@echo "[make] Installing systemd override for code-server"
	@$(run_as_root) mkdir -p $(CODE_SERVER_SYSTEMD_DIR)
	@$(run_as_root) sh -c 'printf "%s\n" \
"[Service]" \
"ExecStart=" \
"ExecStart=/usr/bin/code-server --config $(CODE_SERVER_CONFIG_DST)" \
> "$(CODE_SERVER_SYSTEMD_OVERRIDE)"'
	@$(run_as_root) systemctl daemon-reload

#
# Enable + restart service
#
code-server-enable:
	@echo "[make] Enabling code-server for user $(CODE_SERVER_USER)"
	@$(run_as_root) systemctl enable --now code-server@$(CODE_SERVER_USER)
	@$(run_as_root) systemctl restart code-server@$(CODE_SERVER_USER)

#
# Full workflow
#
code-server: \
	code-server-install \
	code-server-config \
	code-server-systemd \
	code-server-enable
	@echo "🚀 [make] code-server ready on port $(CODE_SERVER_PORT)"
