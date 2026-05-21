# Deploy dnsmasq.conf.add using IFC v2 (constant‑driven, contract‑correct)

ROUTER_DNSMASQ_CONF := /jffs/configs/dnsmasq.conf.add
LOCAL_DNSMASQ_CONF  := $(REPO_ROOT)/router/jffs/configs/dnsmasq.conf.add

.PHONY: router-dnsmasq-conf
router-dnsmasq-conf: secrets-ready ensure-default-gateway router-bootstrap-run-as-root ensure-router-ula router-lan-domain
	@echo "🔧 Installing dnsmasq.conf.add..."
	@set -e; \
	env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(INSTALL_FILE_IF_CHANGED) \
			"" "" "$(LOCAL_DNSMASQ_CONF)" \
			"$(ROUTER_ADDR)" "$(ROUTER_SSH_PORT)" "$(ROUTER_DNSMASQ_CONF)" \
			"root" "root" "0644"; \
	RC=$$?; \
	if [ $$RC -eq 1 ] || [ $$RC -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		echo "🔄 dnsmasq.conf.add changed → restarting dnsmasq + radvd"; \
		$(ROUTER_SSH) "service restart_dnsmasq; service restart_radvd"; \
	else \
		echo "✔️ dnsmasq.conf.add up-to-date"; \
	fi
