# ============================================================
# mk/50_dnsmasq.mk — dnsmasq orchestration
# ============================================================

DNSMASQ_CONF_DIR := /usr/ugreen/etc/dnsmasq/dnsmasq.d
DNSMASQ_CONF_FILE := 99-homelab-listen.conf

DNSMASQ_CONF_SRC := $(HOMELAB_DIR)/config/dnsmasq/$(DNSMASQ_CONF_FILE)
DNSMASQ_CONF_DST := $(DNSMASQ_CONF_DIR)/$(DNSMASQ_CONF_FILE)

.PHONY: install-dnsmasq deploy-dnsmasq-config

install-dnsmasq:
	@$(call apt_install,dnsmasq,dnsmasq)

deploy-dnsmasq-config:
	@echo "📄 [make] Deploying dnsmasq fragment"
	@test -f $(DNSMASQ_CONF_SRC) || { echo "❌ Missing $(DNSMASQ_CONF_SRC)"; exit 1; }
	@$(run_as_root) install -d -m 0755 $(DNSMASQ_CONF_DIR)
	@$(run_as_root) install -m 0644 -o root -g root \
		$(DNSMASQ_CONF_SRC) $(DNSMASQ_CONF_DST)

	@echo "[make] Restarting dnsmasq service"
	@$(run_as_root) systemctl restart dnsmasq
	@$(run_as_root) systemctl is-active --quiet dnsmasq || \
		( echo "❌ dnsmasq failed to start"; \
			$(run_as_root) systemctl status --no-pager dnsmasq; \
			exit 1 )
	@echo "✅ dnsmasq running"
	@echo "✅ dnsmasq fragment deployed"