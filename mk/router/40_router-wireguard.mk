# mk/router/40_router-wireguard.mk
.PHONY: router-sync-wg
router-sync-wg: | router-ssh-check router-require-run-as-root
	$(call deploy_if_changed, \
		$(WG_ROOT)/plan.tsv, \
		$(ROUTER_SCRIPTS)/wireguard/plan.tsv)

	@echo "🔁 Restarting router firewall..."
	ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) "/jffs/scripts/firewall-start"

	@echo "📜 Tailing router logs..."
	ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) "logread -f | grep fw]" &
	sleep 3
	@echo "✅ WireGuard plan synced and firewall restarted"

.PHONY: deploy-wg
deploy-wg: wg-apply router-sync-wg
