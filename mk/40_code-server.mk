# 40_code-server.mk
.PHONY: code-server-install code-server-config code-server-enable code-server

CODE_SERVER_PORT := 8080
CODE_SERVER_CONFIG_SRC := config/code-server/config.yaml
CODE_SERVER_CONFIG_DST := $(HOME)/.config/code-server/config.yaml

code-server-install:
	@if command -v code-server >/dev/null 2>&1; then \
		echo "[make] code-server already installed"; \
	else \
		echo "[make] Installing code-server"; \
		curl -fsSL https://code-server.dev/install.sh | sh; \
	fi

code-server-config:
	@echo "[make] Deploying code-server config"
	@mkdir -p $(dir $(CODE_SERVER_CONFIG_DST))
	@install -m 600 $(CODE_SERVER_CONFIG_SRC) $(CODE_SERVER_CONFIG_DST)

code-server-enable:
	@echo "[make] Enabling code-server for user $(USER)"
	@sudo systemctl enable --now code-server@$(USER)

code-server: code-server-install code-server-config code-server-enable
	@echo "🚀 [make] code-server ready on port $(CODE_SERVER_PORT)"

