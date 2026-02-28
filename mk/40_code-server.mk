# mk/40_code-server.mk
# --------------------------------------------------------------------
.PHONY: \
	code-server-install \
	code-server-enable \
	code-server-ensure-running \
	code-server

CODE_SERVER_PORT := 8080

CODE_SERVER_CONFIG_SRC := $(MAKEFILE_DIR)config/code-server/config.yaml
CODE_SERVER_CONFIG_DST := $(HOME)/.config/code-server/config.yaml

CODE_SERVER_SYSTEMD_DIR := $(SYSTEMD_DIR)/code-server@.service.d
CODE_SERVER_SYSTEMD_OVERRIDE := $(CODE_SERVER_SYSTEMD_DIR)/override.conf

CODE_SERVER_HELPER_DST := $(INSTALL_SBIN_PATH)/systemd-override-sync.sh

$(CODE_SERVER_CONFIG_DST): $(CODE_SERVER_CONFIG_SRC)
	@echo "📄 Updating code-server config"
	@mkdir -p "$(dir $(CODE_SERVER_CONFIG_DST))"
	@install -m 600 "$(CODE_SERVER_CONFIG_SRC)" "$(CODE_SERVER_CONFIG_DST)"

$(CODE_SERVER_SYSTEMD_OVERRIDE): \
	$(CODE_SERVER_CONFIG_DST) \
	$(CODE_SERVER_HELPER_DST)
	@echo "� ️ Ensuring systemd override for code-server"
	@$(run_as_root) mkdir -p "$(CODE_SERVER_SYSTEMD_DIR)"
	@printf '%s\n' \
	    '[Service]' \
	    'ExecStart=' \
	    'ExecStart=/usr/bin/code-server --config $(CODE_SERVER_CONFIG_DST)' | \
	    $(run_as_root) install -m 644 /dev/stdin "$(CODE_SERVER_SYSTEMD_OVERRIDE).new"
	@$(run_as_root) "$(CODE_SERVER_HELPER_DST)" \
	    "$(CODE_SERVER_SYSTEMD_OVERRIDE).new" \
	    "$(CODE_SERVER_SYSTEMD_OVERRIDE)"

code-server-install:
	@if command -v code-server >/dev/null 2>&1; then \
	    echo "🔧 code-server already installed"; \
	else \
	    echo "🔧 Installing code-server"; \
	    curl -fsSL https://code-server.dev/install.sh | sh; \
	fi

code-server-ensure-running: \
	$(CODE_SERVER_CONFIG_DST) \
	$(CODE_SERVER_SYSTEMD_OVERRIDE)
	@$(run_as_root) sh -c '\
	    if systemctl is-active --quiet code-server@$(USER); then \
	        echo "🔁 Restarting code-server (config changed)"; \
	        systemctl restart code-server@$(USER); \
	    else \
	        echo "▶️ Starting code-server"; \
	        systemctl start code-server@$(USER); \
	    fi'

code-server-enable:
	@echo "🔧 Enabling code-server for user $(USER)"
	@$(run_as_root) systemctl enable --now code-server@$(USER)

code-server: \
	code-server-install \
	$(CODE_SERVER_SYSTEMD_OVERRIDE) \
	code-server-enable \
	code-server-ensure-running
	@echo "🚀 code-server ready on port $(CODE_SERVER_PORT)"
