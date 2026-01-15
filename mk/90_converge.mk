# ============================================================
# mk/90_converge.mk — Explicit full network convergence
#
# This target intentionally rewrites WireGuard state:
# - regenerates server configs
# - reassigns client IPs if needed
# - brings up all interfaces
# - reconciles kernel peer state
# - reapplies nftables policy
#
# Intentionally state-rewriting. Requires FORCE=1.
# sudo FORCE=1 make converge-network
# Keeps bin/run-as-root unchanged (argv tokens contract).
# ============================================================
.PHONY: converge-network converge-audit \
		check-force check-forwarding \
		wg-stack regen-clients-fanout network-status \
		wg-converge-server wg-converge-clients wg-converge-runtime

converge-network: check-forwarding check-force \
				  install-homelab-sysctl \
				  firewall-stack \
				  dns-stack dns-runtime \
				  wg-stack
	@echo "✅ Network convergence complete"

converge-audit:
	@echo "🔎 Converge DAG (what would run)"
	@$(MAKE) -n converge-network | sed -n '1,200p'

check-force:
	@if echo "$(MAKEFLAGS)" | grep -q -- '-n'; then \
		echo "[audit] FORCE check skipped"; \
	elif [ "$(FORCE)" != "1" ]; then \
		echo "ERROR: converge-network requires FORCE=1"; \
		echo "       (rewrites WireGuard state)"; \
		exit 1; \
	fi

.PHONY: wg-stack
wg-stack: wg-converge-server wg-converge-clients wg-converge-runtime

regen-clients-fanout: FORCE_REASSIGN=1
regen-clients-fanout: FORCE=1
regen-clients-fanout: CONF_FORCE=1

wg-converge-server:
	$(MAKE) -f $(MAKEFILE_CANONICAL) all-wg CONF_FORCE=1

wg-converge-clients:
	@echo "🔁 Regenerating client configs (sequential, deterministic)"
	$(MAKE) -f $(MAKEFILE_CANONICAL) regen-clients-fanout

wg-converge-runtime:
	$(MAKE) -f $(MAKEFILE_CANONICAL) all-wg-up
	$(MAKE) -f $(MAKEFILE_CANONICAL) wg-add-peers

# Client regeneration fan-out (intentionally sequential for safety)
# Evaluate client interfaces at runtime to avoid parse-time shell traps
.PHONY: regen-clients-fanout
regen-clients-fanout: guard-wg-root
	@for iface in $$($(SCRIPTS)/wg-plan-ifaces.sh "$(WG_ROOT)/compiled/plan.tsv"); do \
		$(MAKE) regen-client-$$iface FORCE_REASSIGN=1 FORCE=1 CONF_FORCE=1; \
	done

.PHONY: guard-wg-root
guard-wg-root:
	@if [ -z "$(WG_ROOT)" ]; then \
		echo "ERROR: WG_ROOT must be set (command line or environment) for regen-clients-fanout"; \
		exit 1; \
	fi

regen-client-%:
	$(MAKE) -f $(MAKEFILE_CANONICAL) regen-clients IFACE=$* \
		FORCE_REASSIGN=1 FORCE=1 CONF_FORCE=1

check-forwarding:
	@$(run_as_root) sysctl -n net.ipv4.ip_forward | grep -q '^1$$' || \
		{ echo "ERROR: IPv4 forwarding disabled"; exit 1; }
	@$(run_as_root) sysctl -n net.ipv6.conf.all.forwarding | grep -q '^1$$' || \
		{ echo "ERROR: IPv6 forwarding disabled"; exit 1; }

.PHONY: network-status

network-status:
	@echo "🔎 Kernel forwarding"
	@$(run_as_root) sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding
	@echo
	@echo "🔎 nftables ruleset"
	@$(run_as_root) nft list table inet homelab_filter
	@$(run_as_root) nft list table ip homelab_nat

.PHONY: firewall-stack
firewall-stack:
	@echo "🔥 Applying homelab nftables firewall"
	@$(run_as_root) bash "$(HOMELAB_DIR)/scripts/homelab-nft-apply.sh"

