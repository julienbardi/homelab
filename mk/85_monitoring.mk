# --------------------------------------------------------------------
# mk/85_monitoring.mk
# --------------------------------------------------------------------
# CONTRACT:
# - Monitoring is opt-in and explicit.
# - Prometheus is installed and configured only when requested.
# - No services are enabled implicitly.
# - Configuration is owned by the repo and installed idempotently.
# --------------------------------------------------------------------

PROMETHEUS_CONFIG_SRC := $(MAKEFILE_DIR)config/prometheus/prometheus.yml
PROMETHEUS_CONFIG_DST := /etc/prometheus/prometheus.yml

PROMETHEUS_ADDR := $(NAS_LAN_IP):9090

PROMETHEUS_SERVICE := prometheus.service

.PHONY: \
	monitoring \
	prometheus \
	prometheus-install \
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
	prometheus-config \
	prometheus-enable \
	prometheus-restart
	@echo "📊 Prometheus UI reachable at: http://$(PROMETHEUS_ADDR)"
	@echo "📊 Targets page shows both jobs UP at: http://$(PROMETHEUS_ADDR)/targets"
	@echo "🚀 Prometheus observability ready"

prometheus-install: ensure-run-as-root
	@echo "📦 Installing Prometheus"
	@$(call apt_update_if_needed)
	@$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
		prometheus

# --------------------------------------------------------------------
# Install Prometheus configuration (repo-owned)
# --------------------------------------------------------------------
prometheus-config: ensure-run-as-root $(PROMETHEUS_CONFIG_SRC)
	@echo "📦 Installing Prometheus configuration"
	@$(call install_file,$(PROMETHEUS_CONFIG_SRC),$(PROMETHEUS_CONFIG_DST),root,root,0644) \
		|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]

# --------------------------------------------------------------------
# Restart Prometheus explicitly
# --------------------------------------------------------------------
prometheus-enable: ensure-run-as-root
	@if ! $(run_as_root) systemctl is-enabled --quiet $(PROMETHEUS_SERVICE); then \
		echo "⚙️ Enabling Prometheus service"; \
		$(run_as_root) systemctl enable $(PROMETHEUS_SERVICE); \
	else \
		echo "💎 Prometheus service already enabled"; \
	fi
	@if ! $(run_as_root) systemctl is-active --quiet $(PROMETHEUS_SERVICE); then \
		echo "▶️ Starting Prometheus service"; \
		$(run_as_root) systemctl start $(PROMETHEUS_SERVICE); \
	else \
		echo "💎 Prometheus service already running"; \
	fi

prometheus-restart: ensure-run-as-root
	@echo "🔁 Restarting Prometheus"
	@$(run_as_root) systemctl daemon-reload
	@$(run_as_root) systemctl restart $(PROMETHEUS_SERVICE)

# --------------------------------------------------------------------
# Status helper
# --------------------------------------------------------------------
prometheus-status: ensure-run-as-root
	@$(run_as_root) systemctl status $(PROMETHEUS_SERVICE) --no-pager
