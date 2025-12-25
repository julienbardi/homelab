# ============================================================
# mk/50_dnsmasq.mk — dnsmasq orchestration
# ============================================================

DNSMASQ_CONF_SRC := $(HOMELAB_DIR)/config/dnsmasq/99-homelab-listen.conf
DNSMASQ_CONF_DST := /etc/dnsmasq.d/99-homelab-listen.conf

.PHONY: install-dnsmasq deploy-dnsmasq-config

install-dnsmasq:
	@$(call apt_install,dnsmasq,dnsmasq)

deploy-dnsmasq-config:
	@echo "📄 [make] Deploying dnsmasq fragment"
	@test -f $(DNSMASQ_CONF_SRC) || { echo "❌ Missing $(DNSMASQ_CONF_SRC)"; exit 1; }
	@$(run_as_root) install -d -m 0755 /etc/dnsmasq.d
	@$(run_as_root) install -m 0644 -o root -g root \
		$(DNSMASQ_CONF_SRC) $(DNSMASQ_CONF_DST)
	@$(run_as_root) systemctl restart dnsmasq
	@echo "✅ dnsmasq fragment deployed"
