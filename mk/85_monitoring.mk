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

# Tracking flags
PROMETHEUS_CHANGED_STAMP := $(STAMP_DIR_ROOT)/prometheus_config_changed.stamp
PROMETHEUS_UNIT_CHANGED_STAMP := $(STAMP_DIR_ROOT)/prometheus_unit_changed.stamp

# Absolute Fast-Path Shadow Targets
PROMETHEUS_CONFIG_SHADOW := $(STAMP_DIR_USER)/prometheus_config.shadow
PROMETHEUS_UNIT_SHADOW := $(STAMP_DIR_USER)/prometheus_unit.shadow

.PHONY: \
	monitoring \
	prometheus \
	prometheus-install \
	prometheus-enable \
	prometheus-restart \
	prometheus-status

# --------------------------------------------------------------------
# Entrypoints
# --------------------------------------------------------------------
monitoring: prometheus
	@echo "📊 Monitoring stack ready"

prometheus: \
	prometheus-install \
	$(PROMETHEUS_UNIT_SHADOW) \
	$(PROMETHEUS_CONFIG_SHADOW) \
	prometheus-enable \
	prometheus-restart
	@echo "📊 Prometheus UI reachable at: http://$(PROMETHEUS_ADDR)"
	@echo "🚀 Prometheus observability ready"

# --------------------------------------------------------------------
# Installation (Gated by binary existence to bypass apt completely)
# --------------------------------------------------------------------
prometheus-install: | ensure-host-default-route
	@if ! command -v prometheus >/dev/null 2>&1; then \
		echo "📦 Installing Prometheus via package toolchain..."; \
		$(call apt_update_if_needed); \
		$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends prometheus; \
	  fi

# --------------------------------------------------------------------
# Systemd Unit Deployment via Shadow Invariant Check
# --------------------------------------------------------------------
$(PROMETHEUS_UNIT_SHADOW): $(PROMETHEUS_UNIT_SRC) $(PROMETHEUS_UNIT_DST) install-all | prometheus-install
	@OLD_HASH=$$(sha256sum "$(PROMETHEUS_UNIT_DST)" 2>/dev/null | awk '{print $$1}') || OLD_HASH=""; \
	NEW_HASH=$$(sha256sum "$(PROMETHEUS_UNIT_SRC)" 2>/dev/null | awk '{print $$1}') || NEW_HASH=""; \
	if [ "$$OLD_HASH" != "$$NEW_HASH" ]; then \
		echo "🔍 Validating Prometheus systemd unit structure"; \
		if command -v systemd-analyze >/dev/null 2>&1; then \
			systemd-analyze verify $(PROMETHEUS_UNIT_SRC) 2>&1 | grep -v "index_serv.service" || true; \
		fi; \
		echo "🔧 Syncing Prometheus systemd unit asset"; \
		$(call install_file,$(PROMETHEUS_UNIT_SRC),$(PROMETHEUS_UNIT_DST),$(ROOT_UID),$(ROOT_GID),0644); \
		touch "$(PROMETHEUS_UNIT_CHANGED_STAMP)"; \
	  fi
	@touch "$@"

# --------------------------------------------------------------------
# Configuration Deployment via Shadow Invariant Check
# --------------------------------------------------------------------
$(PROMETHEUS_CONFIG_SHADOW): $(PROMETHEUS_CONFIG_SRC) install-all | prometheus-install
	@OLD_HASH=$$(sha256sum "$(PROMETHEUS_CONFIG_DST)" 2>/dev/null | awk '{print $$1}') || OLD_HASH=""; \
	NEW_HASH=$$(sha256sum "$(PROMETHEUS_CONFIG_SRC)" 2>/dev/null | awk '{print $$1}') || NEW_HASH=""; \
	if [ "$$OLD_HASH" != "$$NEW_HASH" ]; then \
		echo "🔍 Validating Prometheus configuration"; \
		if ! command -v promtool >/dev/null 2>&1; then \
			echo "ERROR: promtool not found in PATH. Ensure prometheus-install has executed successfully." >&2; \
			exit 1; \
		fi; \
		promtool check config $(PROMETHEUS_CONFIG_SRC); \
		echo "📦 Syncing Prometheus configuration"; \
		$(call install_file,$(PROMETHEUS_CONFIG_SRC),$(PROMETHEUS_CONFIG_DST),$(ROOT_UID),$(ROOT_GID),0644); \
		touch "$(PROMETHEUS_CHANGED_STAMP)"; \
	  fi
	@touch "$@"

# --------------------------------------------------------------------
# Enable and State Management
# --------------------------------------------------------------------
prometheus-enable: $(PROMETHEUS_UNIT_DST)
	@if ! $(run_as_root) systemctl is-enabled --quiet $(PROMETHEUS_SERVICE) 2>/dev/null; then \
		echo "⚙️ Enabling Prometheus service"; \
		$(run_as_root) systemctl enable $(PROMETHEUS_SERVICE); \
	  fi

# --------------------------------------------------------------------
# Service Recycles (Strictly Conditional on Flags)
# --------------------------------------------------------------------
prometheus-restart:
	@NEED_RELOAD=0; NEED_RESTART=0; \
	if [ -f "$(PROMETHEUS_UNIT_CHANGED_STAMP)" ]; then NEED_RELOAD=1; NEED_RESTART=1; fi; \
	if [ -f "$(PROMETHEUS_CHANGED_STAMP)" ]; then NEED_RESTART=1; fi; \
	if [ "$$NEED_RELOAD" -eq 1 ]; then \
		echo "🔄 Prometheus unit changed — executing daemon-reload"; \
		$(run_as_root) systemctl daemon-reload; \
		$(run_as_root) rm -f "$(PROMETHEUS_UNIT_CHANGED_STAMP)"; \
	  fi; \
	if [ "$$NEED_RESTART" -eq 1 ]; then \
		echo "🔄 Prometheus state modification verified — restarting service"; \
		$(run_as_root) systemctl restart $(PROMETHEUS_SERVICE); \
		$(run_as_root) rm -f "$(PROMETHEUS_CHANGED_STAMP)"; \
	  fi

# --------------------------------------------------------------------
# Status Helper
# --------------------------------------------------------------------
prometheus-status:
	@$(run_as_root) systemctl status $(PROMETHEUS_SERVICE) --no-pager

$(PROMETHEUS_UNIT_DST): | install-all
	@changed=0; rc=0; \
	$(call install_file,$(PROMETHEUS_UNIT_SRC),$(PROMETHEUS_UNIT_DST),$(ROOT_UID),$(ROOT_GID),0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 prometheus.service updated — reloading systemd context"; \
		$(systemctl_daemon_reload); \
	fi
