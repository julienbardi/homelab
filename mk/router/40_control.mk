# mk/40_router-control.mk
# ------------------------------------------------------------
# ROUTER CONTROL PLANE — ORCHESTRATION ONLY
# ------------------------------------------------------------

.PHONY: router-disable-asus-ca
router-disable-asus-ca:
	@echo "🛡️ Disabling ASUS internal certificate generation"
	@$(WITH_SECRETS) \
		router_ssh="ssh -p $$router_ssh_port $$router_user@$$router_addr"; \
		$$router_ssh 'set -e; \
			cur_gen="$$(nvram get https_crt_gen 2>/dev/null || echo)"; \
			cur_save="$$(nvram get https_crt_save 2>/dev/null || echo)"; \
			changed=0; \
			if [ "$$cur_gen" != "0" ]; then \
				echo "🔧 Setting https_crt_gen=0"; \
				nvram set https_crt_gen=0; \
				changed=1; \
			fi; \
			if [ "$$cur_save" != "0" ]; then \
				echo "🔧 Setting https_crt_save=0"; \
				nvram set https_crt_save=0; \
				changed=1; \
			fi; \
			if [ "$$changed" -eq 1 ]; then \
				nvram commit; \
				echo "✅ ASUS internal CA disabled"; \
			else \
				echo "ℹ️ ASUS internal CA already converged"; \
			fi'

.PHONY: check-tools
check-tools:
	@echo "🔍 Router capability report"
	@echo
	@command -v ssh >/dev/null 2>&1 \
		&& echo "✅ CAP_REMOTE_EXEC: enabled" \
		|| echo "❌ CAP_REMOTE_EXEC: unavailable"
	@command -v scp >/dev/null 2>&1 \
		&& echo "✅ CAP_FILE_DEPLOY: enabled" \
		|| echo "❌ CAP_FILE_DEPLOY: unavailable"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) \
		'command -v sha256sum >/dev/null 2>&1 || echo test | busybox sha256sum >/dev/null 2>&1' \
		&& echo "✅ CAP_CONTENT_ADDRESSING: enabled" \
		|| echo "⚠️ CAP_CONTENT_ADDRESSING: degraded"
	@ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) '[ -x /jffs/scripts/firewall-start ]' >/dev/null 2>&1 \
		&& echo "✅ CAP_FIREWALL: enabled" \
		|| echo "⚠️ CAP_FIREWALL: degraded"
	@echo
	@echo "ℹ️ Informational only"

# ------------------------------------------------------------
# Router readiness
# ------------------------------------------------------------

.PHONY: router-ready
router-ready: router-firewall-hardened router-dnsmasq-cache
	@echo "🛡️ Router base services converged"

.PHONY: router-prepare
router-prepare: router-ready router-require-run-as-root router-certs-prepare

# ------------------------------------------------------------
# FULL ROUTER CONVERGENCE
# ------------------------------------------------------------

.PHONY: router-bootstrap
router-bootstrap: export ROUTER_BOOTSTRAP=1
router-bootstrap: \
	ensure-default-gateway \
	ensure-router-ula \
	router-install-scripts \
	router-provision-nvram \
	router-dhcp-range-ensure \
	router-dhcp-static-ensure \
	router-dnsmasq-sync \
	install-ssh-config \
	router-ddns \
	router-firewall-install \
	router-disable-asus-ca
	@echo "🛠️ Router bootstrap complete"

.PHONY: router-converge
router-converge: \
	router-ssh-check \
	router-bootstrap \
	router-firewall-hardened \
	router-certs-deploy \
	router-caddy \
	router-wg-check \
	router-health \
	router-health-strict
	@echo "🚀 Router fully converged"

.PHONY: router-all
router-all: router-converge

.PHONY: router-verify
router-verify: \
	router-ssh-check \
	router-firewall-hardened \
	router-wg-health-strict \
	router-wg-audit \
	router-health-strict
	@echo "✅ Router verification passed"
