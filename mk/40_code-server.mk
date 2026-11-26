# mk/40_code-server.mk
# --------------------------------------------------------------------
.PHONY: \
	code-server-install \
	code-server-enable \
	code-server-ensure-running \
	code-server

CODE_SERVER_BIND_ADDR := 0.0.0.0
CODE_SERVER_PORT := 18080

CODE_SERVER_CONFIG_DST := $(HOME)/.config/code-server/config.yaml

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

$(CODE_SERVER_CONFIG_DST): |  $(run_as_root) $(INSTALL_FILE_IF_CHANGED)
	@echo "📋 Rendering code-server config"

	@install -d -m 0700 "$(dir $(CODE_SERVER_CONFIG_DST))"

	@tmp="$$(mktemp)"; \
	printf '%s\n' \
		"bind-addr: $(CODE_SERVER_BIND_ADDR):$(CODE_SERVER_PORT)" \
		"auth: none" \
		"cert: false" \
	> "$$tmp"; \
	$(call install_file,$$tmp,$(CODE_SERVER_CONFIG_DST),$(USER_UID),$(USER_GID),0600); \
	rm -f "$$tmp"

$(CODE_SERVER_SYSTEMD_OVERRIDE): $(CODE_SERVER_CONFIG_DST) | $(run_as_root) $(INSTALL_FILE_IF_CHANGED)
	@[ "$(VERBOSE)" -ge 1 ] && \
		echo "🛠️ Ensuring systemd override for code-server" || true

	@$(run_as_root) mkdir -p "$(CODE_SERVER_SYSTEMD_DIR)"

	@printf '%s\n' \
	'[Service]' \
	'ExecStart=' \
	'ExecStart=/usr/bin/code-server --config $(CODE_SERVER_CONFIG_DST)' | \
	$(run_as_root) install -m 644 /dev/stdin "$(CODE_SERVER_SYSTEMD_OVERRIDE).new"

	@$(run_as_root) sh -eu -c '\
	rc=0; \
	$(INSTALL_FILE_IF_CHANGED) \
	"" "" "$(CODE_SERVER_SYSTEMD_OVERRIDE).new" \
	"" "" "$(CODE_SERVER_SYSTEMD_OVERRIDE)" \
	root root 644 \
	|| rc=$$?; \
	rm -f "$(CODE_SERVER_SYSTEMD_OVERRIDE).new"; \
	if [ $$rc -eq $(INSTALL_IF_CHANGED_EXIT_UNCHANGED) ]; then \
		[ "$(VERBOSE)" -ge 1 ] && \
			echo "📝 systemd override unchanged" || true; \
	elif [ $$rc -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		echo "🛠️ Updating systemd override"; \
		systemctl daemon-reload; \
	else \
		echo "❌ IFC error (code $$rc)" >&2; \
		exit $$rc; \
	fi'

code-server-install:
	@if command -v code-server >/dev/null 2>&1; then \
		if [ "$(VERBOSE)" -ge 1 ]; then \
			echo "🟢 code-server already installed"; \
		fi; \
	else \
		echo "📦 Installing code-server"; \
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

code-server-ensure-running: code-server-enable
	@$(run_as_root) sh -eu -c '\
	if systemctl is-active --quiet code-server@$(USER); then \
		echo "🔄 Restarting code-server"; \
		systemctl restart code-server@$(USER); \
	else \
		echo "🚀 Starting code-server"; \
		systemctl start code-server@$(USER); \
	fi; \
	sleep 1; \
	systemctl is-active --quiet code-server@$(USER) || { \
		echo "❌ code-server failed to start"; \
		exit 1; \
	}; \
	if [ "$(VERBOSE)" -ge 1 ]; then \
		echo "✅ code-server active"; \
	fi; \
	'

code-server-enable: $(CODE_SERVER_CONFIG_DST) $(CODE_SERVER_SYSTEMD_OVERRIDE)
	@if $(run_as_root) systemctl is-enabled --quiet code-server@$(USER) 2>/dev/null; then \
		if [ "$(VERBOSE)" -ge 1 ]; then \
			echo "🟢 code-server already enabled"; \
		fi; \
	else \
		echo "🔧 Enabling code-server for user $(USER)"; \
		$(run_as_root) systemctl enable --now code-server@$(USER); \
	fi

code-server: \
	code-server-install \
	$(CODE_SERVER_SYSTEMD_OVERRIDE) \
	code-server-enable \
	code-server-ensure-running
