# ============================================================
# mk/65_dnsmasq.mk — Local DNS Forwarder & DHCP
# ============================================================

# Global variables required by other modules (e.g., Caddy/Graph)
CADDY_INTERNAL_HOSTS_FILE := $(REPO_ROOT)config/caddy/internal-hosts.txt

# Configuration Paths
DNSMASQ_CONF_SRC      := $(REPO_ROOT)config/dnsmasq/dnsmasq.conf
DNSMASQ_CONF_DST      := /etc/dnsmasq.conf
DNSMASQ_FRAGMENTS_SRC := $(REPO_ROOT)config/dnsmasq
DNSMASQ_UGREEN_DIR    := /usr/ugreen/etc/dnsmasq/dnsmasq.d

.PHONY: \
    enable-dnsmasq \
    install-pkg-dnsmasq \
    deploy-dnsmasq-config \
    dnsmasq-health \
    disable-resolved

# --- Main Entry Point ---
enable-dnsmasq: \
    assert-unbound-running \
    disable-resolved \
    install-pkg-dnsmasq \
    deploy-dnsmasq-config
	@echo "🔄 Restarting dnsmasq"
	@$(run_as_root) systemctl restart dnsmasq
	@$(run_as_root) systemctl is-active --quiet dnsmasq || (echo "❌ Failed"; exit 1)
	@dig @127.0.0.1 google.com +short +tries=1 +time=2 >/dev/null || (echo "❌ DNS Fail"; exit 1)
	@echo "✅ dnsmasq healthy"

# --- Installation ---
install-pkg-dnsmasq:
	@echo "📦 Installing dnsmasq"
	@$(call apt_install,dnsmasq,dnsmasq)

# --- Configuration (Merged Logic) ---
deploy-dnsmasq-config: ensure-run-as-root
	@echo "🔍 Validating main config"
	@$(run_as_root) dnsmasq --test --conf-file=$(DNSMASQ_CONF_SRC) || exit 1
	@$(call install_file,$(DNSMASQ_CONF_SRC),$(DNSMASQ_CONF_DST),root,root,0644)

	@echo "📄 Deploying dnsmasq fragments to UGOS path"
	@$(run_as_root) install -d -m 0755 $(DNSMASQ_UGREEN_DIR)
	@for f in $(wildcard $(DNSMASQ_FRAGMENTS_SRC)/*.conf); do \
		$(call install_file,$$f,$(DNSMASQ_UGREEN_DIR)/$$(basename $$f),root,root,0644); \
	done

# --- Conflicts ---
disable-resolved: ensure-run-as-root
	@if systemctl is-active --quiet systemd-resolved; then \
		echo "🛑 Disabling systemd-resolved"; \
		$(run_as_root) systemctl disable --now systemd-resolved || true; \
		echo "nameserver 127.0.0.1" | $(run_as_root) tee /etc/resolv.conf >/dev/null; \
	fi

# --- Health Check ---
dnsmasq-health:
	@dig @127.0.0.1 google.com +short +tries=1 +time=2 >/dev/null && echo "✅ OK" || echo "❌ Fail"