# ============================================================
# mk/50_dnsmasq.mk — dnsmasq orchestration
# ============================================================

DNSMASQ_CONF_SRC_DIR := $(HOMELAB_DIR)/config/dnsmasq
DNSMASQ_CONF_FILES := $(wildcard $(DNSMASQ_CONF_SRC_DIR)/*.conf)

DNSMASQ_CONF_DIR := /usr/ugreen/etc/dnsmasq/dnsmasq.d

CADDY_INTERNAL_HOSTS_FILE := $(HOMELAB_DIR)/config/caddy/internal-hosts.txt

.PHONY: \
	install-pkg-dnsmasq \
	deploy-dnsmasq-config \
	check-dnsmasq-udp-buffers \
	apply-dnsmasq-udp-buffers \
	restore-dnsmasq-udp-buffers

install-pkg-dnsmasq:
	@echo "📦 Installing dnsmasq"
	$(call apt_install,dnsmasq,dnsmasq)
	@echo "✅ dnsmasq package installed"

remove-pkg-dnsmasq:
	@echo "🗑️ Removing dnsmasq"
	@$(run_as_root) systemctl stop dnsmasq >/dev/null 2>&1 || true
	@$(run_as_root) systemctl disable dnsmasq >/dev/null 2>&1 || true
	$(call apt_remove,dnsmasq)
	@echo "✅ dnsmasq removed"

deploy-dnsmasq-config: install-pkg-dnsmasq apply-dnsmasq-udp-buffers
	@echo "📄 [make] Deploying dnsmasq fragments"
	@test -d $(DNSMASQ_CONF_SRC_DIR) || { echo "❌ Missing $(DNSMASQ_CONF_SRC_DIR)"; exit 1; }

	@$(run_as_root) install -d -m 0755 $(DNSMASQ_CONF_DIR)
	@for f in $(DNSMASQ_CONF_FILES); do \
		echo "  → $$(basename $$f)"; \
		$(run_as_root) install -m 0644 -o root -g root $$f $(DNSMASQ_CONF_DIR)/$$(basename $$f); \
	done

	@echo "[make] Restarting dnsmasq service"
	@$(run_as_root) systemctl restart dnsmasq
	@$(run_as_root) systemctl is-active --quiet dnsmasq || \
		( echo "❌ dnsmasq failed to start"; \
			$(run_as_root) systemctl status --no-pager dnsmasq; \
			exit 1 )

	@echo "✅ dnsmasq running"
	@echo "✅ dnsmasq fragments deployed"

check-dnsmasq-udp-buffers:
	@echo "🔍 Checking kernel UDP receive buffers for dnsmasq (UGOS defaults: net.core.rmem_max = 8388608, net.core.rmem_default = 212992)"
	@$(run_as_root) sh -eu -c '\
		REQUIRED=8388608; \
		CUR_MAX=$$(sysctl -n net.core.rmem_max); \
		CUR_DEF=$$(sysctl -n net.core.rmem_default); \
		if [ $$CUR_MAX -lt $$REQUIRED ] || [ $$CUR_DEF -lt $$REQUIRED ]; then \
			echo "❌ UDP receive buffers too small"; \
			exit 1; \
		fi; \
		echo "✅ UDP receive buffers OK"'

apply-dnsmasq-udp-buffers:
	@echo "🔧 Applying UDP receive buffer tuning for dnsmasq"
	@$(run_as_root) sysctl -w net.core.rmem_max=8388608
	@$(run_as_root) sysctl -w net.core.rmem_default=8388608

restore-dnsmasq-udp-buffers:
	@echo "↩️  [make] Restoring UGOS UDP buffer defaults"
	@$(run_as_root) sh -eu -c '\
		sysctl -w net.core.rmem_max=8388608 >/dev/null; \
		sysctl -w net.core.rmem_default=212992 >/dev/null; \
		echo "✅ [make] UGOS defaults restored"'

