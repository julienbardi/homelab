# mk/72_pangolin.mk

PANGOLIN_DIR         := /etc/pangolin
PANGOLIN_SECRET      := $(PANGOLIN_DIR)/site-secret
PANGOLIN_BIN         := $(INSTALL_PATH)/pangolin-site-agent
PANGOLIN_SERVICE     := /etc/systemd/system/pangolin-site-agent.service
PANGOLIN_URL         := https://install.pangolin.dev/site-agent/latest/pangolin-site-agent-linux-amd64
PANGOLIN_SERVICE_SRC := $(MAKEFILE_DIR)config/systemd/pangolin-site-agent.service

.PHONY: pangolin-install pangolin-enable pangolin-status pangolin-health pangolin-node-check

pangolin-install: ensure-run-as-root pangolin-node-check
	@echo "📦 Installing Pangolin Site Agent..."
	@$(run_as_root) mkdir -p $(PANGOLIN_DIR)
	@$(run_as_root) chmod 700 $(PANGOLIN_DIR)

	@if [ ! -f $(PANGOLIN_SECRET) ]; then \
		echo "❌ Missing Pangolin site-secret"; \
		echo "👉 Create it at $(PANGOLIN_SECRET)"; \
		exit 1; \
	fi

	@echo "⬇️  Installing Pangolin binary (IFC v2)..."
	@$(run_as_root) $(INSTALL_URL_FILE_IF_CHANGED) \
		"$(PANGOLIN_URL)" \
		"$(PANGOLIN_BIN)" \
		"root" "root" "0755"

	@echo "⚙️ Installing systemd service..."
	@$(run_as_root) $(INSTALL_FILES_IF_CHANGED) \
		"$(PANGOLIN_SERVICE_SRC)" \
		"$(PANGOLIN_SERVICE)" \
		"root" "root" "0644"

	@$(run_as_root) systemctl daemon-reload
	@echo "✅ Pangolin install complete"

pangolin-enable: ensure-run-as-root pangolin-install
	@echo "🚀 Enabling Pangolin Site Agent..."
	@$(run_as_root) systemctl enable --now pangolin-site-agent.service
	@$(run_as_root) systemctl is-active --quiet pangolin-site-agent.service && \
		echo "   ✅ Agent active" || echo "   ❌ Agent not running"

pangolin-status: ensure-run-as-root
	@$(run_as_root) systemctl status pangolin-site-agent.service --no-pager || true

pangolin-health: ensure-run-as-root
	@echo "🔍 Pangolin Agent Health"
	@if $(run_as_root) systemctl is-active --quiet pangolin-site-agent.service; then \
		echo "   ✅ Service active"; \
	else \
		echo "   ❌ Service inactive"; \
	fi

pangolin-node-check:
	@if ! $(run_as_root) systemctl status pangolin-node.service >/dev/null 2>&1; then \
		echo "❌ Pangolin Node Agent not detected."; \
		echo "👉 You must install the Pangolin Node first:"; \
		echo ""; \
		echo "   curl -fsSL https://install.pangolin.dev/node/install.sh | sudo bash"; \
		echo ""; \
		echo "After installing the Node, create a Local Site in the Pangolin UI,"; \
		echo "then place the site-secret at $(PANGOLIN_SECRET)."; \
		exit 1; \
	fi
