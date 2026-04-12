# mk/73_pangolin_selfhost.mk
#
# Self-hosted Pangolin Site Agent
# This block is fully isolated from the Cloud version (mk/72_pangolin.mk).
# It uses your own backend at https://pangolin.bardi.ch.

PANGOLIN_SELF_DIR         := /etc/pangolin
PANGOLIN_SELF_SECRET      := $(PANGOLIN_SELF_DIR)/site-secret
PANGOLIN_SELF_BIN         := $(INSTALL_PATH)/pangolin-site-agent
PANGOLIN_SELF_SERVICE     := /etc/systemd/system/pangolin-site-agent-selfhost.service
PANGOLIN_SELF_URL         := https://pangolin.bardi.ch/api/agent/site/download
PANGOLIN_SELF_SERVICE_SRC := $(REPO_ROOT)config/systemd/pangolin-site-agent-selfhost.service

.PHONY: pangolin-selfhost-install pangolin-selfhost-enable pangolin-selfhost-status pangolin-selfhost-health

pangolin-selfhost-install: ensure-run-as-root
	@echo "📦 Installing *self-hosted* Pangolin Site Agent..."
	@$(run_as_root) mkdir -p $(PANGOLIN_SELF_DIR)
	@$(run_as_root) chmod 700 $(PANGOLIN_SELF_DIR)

	@if [ ! -f $(PANGOLIN_SELF_SECRET) ]; then \
		echo "❌ Missing self-hosted Pangolin site-secret"; \
		echo "👉 Create it at $(PANGOLIN_SELF_SECRET) (from your self-hosted UI)"; \
		exit 1; \
	fi

	@echo "⬇️  Installing Pangolin Site Agent binary (self-hosted)..."
	@$(run_as_root) $(INSTALL_URL_FILE_IF_CHANGED) \
		"$(PANGOLIN_SELF_URL)" \
		"$(PANGOLIN_SELF_BIN)" \
		"root" "root" "0755"

	@echo "⚙️ Installing systemd service (self-hosted)..."
	@$(run_as_root) $(INSTALL_FILES_IF_CHANGED) \
		"$(PANGOLIN_SELF_SERVICE_SRC)" \
		"$(PANGOLIN_SELF_SERVICE)" \
		"root" "root" "0644"

	@$(run_as_root) systemctl daemon-reload
	@echo "✅ Self-hosted Pangolin install complete"

pangolin-selfhost-enable: ensure-run-as-root pangolin-selfhost-install
	@echo "🚀 Enabling self-hosted Pangolin Site Agent..."
	@$(run_as_root) systemctl enable --now pangolin-site-agent-selfhost.service
	@$(run_as_root) systemctl is-active --quiet pangolin-site-agent-selfhost.service && \
		echo "   ✅ Agent active" || echo "   ❌ Agent not running"

pangolin-selfhost-status: ensure-run-as-root
	@$(run_as_root) systemctl status pangolin-site-agent-selfhost.service --no-pager || true

pangolin-selfhost-health: ensure-run-as-root
	@echo "🔍 Self-hosted Pangolin Agent Health"
	@if $(run_as_root) systemctl is-active --quiet pangolin-site-agent-selfhost.service; then \
		echo "   ✅ Service active"; \
	else \
		echo "   ❌ Service inactive"; \
	fi
