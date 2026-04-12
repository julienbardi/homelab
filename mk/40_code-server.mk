# mk/40_code-server.mk
# --------------------------------------------------------------------
.PHONY: \
	code-server-install \
	code-server-enable \
	code-server-ensure-running \
	code-server

CODE_SERVER_PORT = 8080

CODE_SERVER_CONFIG_SRC = $(REPO_ROOT)config/code-server/config.yaml
CODE_SERVER_CONFIG_DST = $(HOME)/.config/code-server/config.yaml

CODE_SERVER_SYSTEMD_DIR = $(SYSTEMD_DIR)/code-server@.service.d
CODE_SERVER_SYSTEMD_OVERRIDE = $(CODE_SERVER_SYSTEMD_DIR)/override.conf

# Detect installed version (semantic only)
CODE_SERVER_INSTALLED_VERSION = $(shell code-server --version 2>/dev/null | head -n1 | awk '{print $$1}')

# Fetch latest version from GitHub API (= for deferred expansion)
CODE_SERVER_LATEST_VERSION = $(shell curl -fsSL https://api.github.com/repos/coder/code-server/releases/latest | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')

# Helper: compare versions
code-server-version-check:
	@echo "Installed: $(CODE_SERVER_INSTALLED_VERSION)"
	@echo "Latest:    $(CODE_SERVER_LATEST_VERSION)"
	@if [ "$(CODE_SERVER_INSTALLED_VERSION)" = "$(CODE_SERVER_LATEST_VERSION)" ]; then \
		echo "📝 code-server is up to date"; \
	else \
		echo "⬆️ Update available: $(CODE_SERVER_INSTALLED_VERSION) -> $(CODE_SERVER_LATEST_VERSION)"; \
	fi

$(CODE_SERVER_CONFIG_DST): $(CODE_SERVER_CONFIG_SRC)
	@echo "📄 Updating code-server config"
	@mkdir -p "$(dir $(CODE_SERVER_CONFIG_DST))"
	@install -m 600 "$(CODE_SERVER_CONFIG_SRC)" "$(CODE_SERVER_CONFIG_DST)"

$(CODE_SERVER_SYSTEMD_OVERRIDE): \
	$(CODE_SERVER_CONFIG_DST)
	@echo "🛠️ Ensuring systemd override for code-server"
	@$(run_as_root) mkdir -p "$(CODE_SERVER_SYSTEMD_DIR)"
	@printf '%s\n' \
		'[Service]' \
		'ExecStart=' \
		'ExecStart=/usr/bin/code-server --config $(CODE_SERVER_CONFIG_DST)' | \
		$(run_as_root) install -m 644 /dev/stdin "$(CODE_SERVER_SYSTEMD_OVERRIDE).new"
	@echo "🛠️ Syncing systemd override (IFC v2)"
	@$(run_as_root) sh -c '\
		/usr/local/bin/install_file_if_changed_v2.sh \
			"" "" "$(CODE_SERVER_SYSTEMD_OVERRIDE).new" \
			"" "" "$(CODE_SERVER_SYSTEMD_OVERRIDE)" \
			root root 644; \
		rc=$$?; \
		rm -f "$(CODE_SERVER_SYSTEMD_OVERRIDE).new"; \
		if [ $$rc -eq 0 ]; then \
			echo "📝 systemd override unchanged"; \
		elif [ $$rc -eq 3 ]; then \
			echo "🛠️ Updating systemd override"; \
			systemctl daemon-reload; \
		else \
			echo "❌ IFC v2 error (code $$rc)" >&2; \
			exit $$rc; \
		fi'

code-server-install:
	@if command -v code-server >/dev/null 2>&1; then \
		echo "🔧 code-server already installed"; \
	else \
		echo "🔧 Installing code-server"; \
		curl -fsSL https://code-server.dev/install.sh | sh; \
	fi

code-server-update:
	@if [ "$(CODE_SERVER_INSTALLED_VERSION)" = "$(CODE_SERVER_LATEST_VERSION)" ]; then \
		echo "📝 code-server already at latest version ($(CODE_SERVER_INSTALLED_VERSION))"; \
	else \
		echo "⬆️ Updating code-server to $(CODE_SERVER_LATEST_VERSION)"; \
		curl -fsSL https://code-server.dev/install.sh | sh; \
		echo "🔄 Restarting code-server service"; \
		$(run_as_root) systemctl daemon-reload; \
		$(run_as_root) systemctl restart code-server@$(USER); \
		echo "📝 Update complete"; \
	fi

code-server-ensure-running: \
	$(CODE_SERVER_CONFIG_DST) \
	$(CODE_SERVER_SYSTEMD_OVERRIDE)
	@$(run_as_root) sh -c '\
		if systemctl is-active --quiet code-server@$(USER); then \
			echo "🔄 Restarting code-server (wait 20 seconds before running this again)"; \
			systemctl restart code-server@$(USER); \
		else \
			echo "🚀 Starting code-server (wait 20 seconds before running this again)"; \
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
