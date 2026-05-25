# ============================================================
# mk/65_dnsmasq.mk — Local DNS Forwarder (NAS)
# ============================================================

# Global variables required by other modules (e.g., Caddy/Graph)
CADDY_INTERNAL_HOSTS_FILE := $(REPO_ROOT)/config/caddy/internal-hosts.txt

# Configuration Paths (NAS only)
DNSMASQ_FRAGMENTS_SRC := $(REPO_ROOT)/config/dnsmasq
DNSMASQ_UGREEN_DIR    := /usr/ugreen/etc/dnsmasq/dnsmasq.d
DNSMASQ_UGREEN_BASE   := /usr/ugreen/etc/dnsmasq/dnsmasq.conf

.PHONY: \
	enable-dnsmasq \
	install-pkg-dnsmasq \
	deploy-dnsmasq-config \
	dnsmasq-health \
	disable-resolved \
	check-ugreen-dnsmasq-file

# --- Main Entry Point ---
enable-dnsmasq: \
	assert-unbound-running \
	disable-resolved \
	install-pkg-dnsmasq \
	deploy-dnsmasq-config
	@echo "🔄 Restarting dnsmasq"
	@$(run_as_root) systemctl restart dnsmasq
	@$(run_as_root) systemctl is-active --quiet dnsmasq || (echo "❌ Failed"; exit 1)

	@echo "🔍 Testing DNS resolution (user context)"
	@dig @127.0.0.1 google.com +short +tries=1 +time=2 >/dev/null || (echo "❌ Loopback DNS fail"; exit 1)
	@dig @$(NAS_LAN_IP) google.com +short +tries=1 +time=2 >/dev/null || (echo "❌ LAN IPv4 DNS fail"; exit 1)
ifdef NAS_LAN_IP6
	@dig @$(NAS_LAN_IP6) google.com AAAA +short +tries=1 +time=2 >/dev/null || (echo "❌ ULA IPv6 DNS fail"; exit 1)
endif
	@echo "✅ dnsmasq healthy"

# --- Installation ---
install-pkg-dnsmasq:
	@echo "📦 Installing dnsmasq"
	@$(call apt_install,dnsmasq,dnsmasq)

# --- UGOS base file existence guard ---
check-ugreen-dnsmasq-file:
	@if [ ! -f "$(DNSMASQ_UGREEN_BASE)" ]; then \
		echo "❌ UGOS base dnsmasq.conf missing"; \
		echo "   Expected: $(DNSMASQ_UGREEN_BASE)"; \
		echo "   This file is part of UGOS firmware and not managed by homelab."; \
		exit 1; \
	fi

# --- Configuration (Fragments Only) ---
deploy-dnsmasq-config: ensure-run-as-root check-ugreen-dnsmasq-file
	@echo "📄 Deploying dnsmasq fragments to UGOS path"
	@$(run_as_root) install -d -m 0755 $(DNSMASQ_UGREEN_DIR)
	# Render dnsmasq templates with variable substitution
	@for f in $(wildcard $(DNSMASQ_FRAGMENTS_SRC)/*.conf); do \
		out="$(DNSMASQ_UGREEN_DIR)/$$(basename $$f)"; \
		echo "🔧 Rendering $$f → $$out"; \
		DOMAIN=$(DOMAIN) \
		NAS_LAN_IP=$(NAS_LAN_IP) \
		LAN_NAS=$(LAN_NAS) \
		LAN_ROUTER=$(LAN_ROUTER) \
		envsubst < $$f > /tmp/dnsmasq.rendered; \
		$(call install_file,/tmp/dnsmasq.rendered,$$out,root,root,0644); \
	done

# --- Conflicts ---
disable-resolved: ensure-run-as-root
	@if systemctl is-active --quiet systemd-resolved; then \
		echo "🛑 Disabling systemd-resolved"; \
		$(run_as_root) systemctl disable --now systemd-resolved || true; \
		echo "nameserver 127.0.0.1" | $(run_as_root) tee /etc/resolv.conf >/dev/null; \
	fi

# --- Health Check ---
# --- Health Check ---
dnsmasq-health:
	@echo "🔍 Testing DNS via 127.0.0.1 (loopback)"
	@dig @127.0.0.1 google.com +short +tries=1 +time=2 >/dev/null || (echo "❌ Loopback DNS fail"; exit 1)

	@echo "🔍 Testing DNS via $(NAS_LAN_IP) (LAN IPv4)"
	@dig @$(NAS_LAN_IP) google.com +short +tries=1 +time=2 >/dev/null || (echo "❌ LAN IPv4 DNS fail"; exit 1)

ifdef NAS_LAN_IP6
	@echo "🔍 Testing DNS via $(NAS_LAN_IP6) (ULA IPv6)"
	@dig @$(NAS_LAN_IP6) google.com AAAA +short +tries=1 +time=2 >/dev/null || (echo "❌ ULA IPv6 DNS fail"; exit 1)
endif

	@echo "✅ dnsmasq healthy (IPv4 + IPv6 + loopback)"


