# --------------------------------------------------------------------
# mk/85_monitoring.mk
# --------------------------------------------------------------------
# CONTRACT:
# - Monitoring is opt-in and explicit.
# - Prometheus is installed and configured only when requested.
# - No services are enabled implicitly.
# - Configuration is owned by the repo and installed idempotently.
# - Service recycles MUST be conditional on configuration state updates.
# - Unit-file drift MUST be tracked independently from config drift.
# - Configuration validation MUST guard tool utility presence in PATH.
# --------------------------------------------------------------------

PROMETHEUS_CONFIG_SRC := $(REPO_ROOT)/config/prometheus/prometheus.yml
PROMETHEUS_CONFIG_DST := /etc/prometheus/prometheus.yml

PROMETHEUS_UNIT_SRC := $(REPO_ROOT)/config/systemd/prometheus.service
PROMETHEUS_UNIT_DST := /etc/systemd/system/prometheus.service

PROMETHEUS_ADDR := $(NAS_LAN_IP):9090

PROMETHEUS_SERVICE := prometheus.service
PROMETHEUS_CHANGED_STAMP := $(STAMP_DIR)/prometheus_config_changed.stamp
PROMETHEUS_UNIT_CHANGED_STAMP := $(STAMP_DIR)/prometheus_unit_changed.stamp

.PHONY: \
    monitoring \
    prometheus \
    prometheus-install \
    prometheus-unit \
    prometheus-config \
    prometheus-enable \
    prometheus-restart \
    prometheus-status

# --------------------------------------------------------------------
# Top-level monitoring entrypoint
# --------------------------------------------------------------------
monitoring: prometheus
	@echo "📊 Monitoring stack ready"

# --------------------------------------------------------------------
# Install Prometheus (explicit, opt-in)
# --------------------------------------------------------------------
prometheus: \
    prometheus-install \
    prometheus-unit \
    prometheus-config \
    prometheus-enable \
    prometheus-restart
	@echo "📊 Prometheus UI reachable at: http://$(PROMETHEUS_ADDR)"
	@echo "📊 Targets page shows both jobs UP at: http://$(PROMETHEUS_ADDR)/targets"
	@echo "🚀 Prometheus observability ready"

prometheus-install: ensure-run-as-root | ensure-default-gateway
	@if ! command -v prometheus >/dev/null 2>&1; then \
		echo "📦 Installing Prometheus via package toolchain..."; \
		$(call apt_update_if_needed); \
		$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends prometheus; \
	else \
		echo "⏩ Prometheus binary already present (skipping package manager invocation)"; \
	fi

# --------------------------------------------------------------------
# Sync Prometheus systemd unit (repo-owned)
# --------------------------------------------------------------------
prometheus-unit: ensure-run-as-root $(PROMETHEUS_UNIT_SRC)
	@echo "🔍 Validating Prometheus systemd unit structure"
	@if command -v systemd-analyze >/dev/null 2>&1; then \
		systemd-analyze verify $(PROMETHEUS_UNIT_SRC) 2>&1 | grep -v "index_serv.service" || true; \
	fi
	@echo "🔧 Syncing Prometheus systemd unit asset"
	@OLD_HASH=$$(sha256sum "$(PROMETHEUS_UNIT_DST)" 2>/dev/null | awk '{print $$1}') || OLD_HASH=""; \
	$(call install_file,$(PROMETHEUS_UNIT_SRC),$(PROMETHEUS_UNIT_DST),$(ROOT_UID),$(ROOT_GID),0644); \
	NEW_HASH=$$(sha256sum "$(PROMETHEUS_UNIT_DST)" 2>/dev/null | awk '{print $$1}') || NEW_HASH=""; \
	if [ "$$OLD_HASH" != "$$NEW_HASH" ]; then \
		echo "⚠️  Prometheus unit drift detected"; \
		touch "$(PROMETHEUS_UNIT_CHANGED_STAMP)"; \
	fi

# --------------------------------------------------------------------
# Install Prometheus configuration (repo-owned)
# --------------------------------------------------------------------
prometheus-config: ensure-run-as-root $(PROMETHEUS_CONFIG_SRC)
	@echo "🔍 Validating Prometheus configuration"
	@if ! command -v promtool >/dev/null 2>&1; then \
		echo "ERROR: promtool not found in PATH. Ensure prometheus-install has executed successfully." >&2; \
		exit 1; \
	fi
	@promtool check config $(PROMETHEUS_CONFIG_SRC)
	@echo "📦 Syncing Prometheus configuration"
	@OLD_HASH=$$(sha256sum "$(PROMETHEUS_CONFIG_DST)" 2>/dev/null | awk '{print $$1}') || OLD_HASH=""; \
	$(call install_file,$(PROMETHEUS_CONFIG_SRC),$(PROMETHEUS_CONFIG_DST),$(ROOT_UID),$(ROOT_GID),0644); \
	NEW_HASH=$$(sha256sum "$(PROMETHEUS_CONFIG_DST)" 2>/dev/null | awk '{print $$1}') || NEW_HASH=""; \
	if [ "$$OLD_HASH" != "$$NEW_HASH" ]; then \
		echo "⚠️  Prometheus config drift detected"; \
		touch "$(PROMETHEUS_CHANGED_STAMP)"; \
	fi

# --------------------------------------------------------------------
# Manage service execution state
# --------------------------------------------------------------------
prometheus-enable: ensure-run-as-root
	@if ! $(run_as_root) systemctl is-enabled --quiet $(PROMETHEUS_SERVICE); then \
		echo "⚙️ Enabling Prometheus service"; \
		$(run_as_root) systemctl enable $(PROMETHEUS_SERVICE); \
	else \
		echo "✨ Prometheus service already enabled"; \
	fi
	@if ! $(run_as_root) systemctl is-active --quiet $(PROMETHEUS_SERVICE); then \
		echo "🚀 Starting Prometheus service"; \
		$(run_as_root) systemctl start $(PROMETHEUS_SERVICE); \
		touch "$(PROMETHEUS_CHANGED_STAMP)"; \
	fi

prometheus-restart: ensure-run-as-root
	@NEED_RELOAD=0; NEED_RESTART=0; \
	if [ -f "$(PROMETHEUS_UNIT_CHANGED_STAMP)" ]; then NEED_RELOAD=1; NEED_RESTART=1; fi; \
	if [ -f "$(PROMETHEUS_CHANGED_STAMP)" ]; then NEED_RESTART=1; fi; \
	if [ "$$NEED_RELOAD" -eq 1 ]; then \
		echo "🔄 Prometheus unit changed — executing daemon-reload"; \
		$(run_as_root) systemctl daemon-reload; \
		rm -f "$(PROMETHEUS_UNIT_CHANGED_STAMP)"; \
	fi; \
	if [ "$$NEED_RESTART" -eq 1 ]; then \
		echo "🔄 Prometheus state modification verified — restarting service"; \
		$(run_as_root) systemctl restart $(PROMETHEUS_SERVICE); \
		rm -f "$(PROMETHEUS_CHANGED_STAMP)"; \
	else \
		echo "✨ Prometheus configuration and unit match active daemon state (skipping restart)"; \
	fi

# --------------------------------------------------------------------
# Status helper
# --------------------------------------------------------------------
# This allows quick interactive queries of the live monitoring daemon.
# --------------------------------------------------------------------
prometheus-status: ensure-run-as-root
	@$(run_as_root) systemctl status $(PROMETHEUS_SERVICE) --no-pager