# ============================================================
# mk/90_converge.mk — Explicit network convergence (safe by default)
# ============================================================
# NOTE:
# - converge-network verifies and reconciles network state
# - Safe by default: no live mutation without FORCE=1
# - Intended for steady-state convergence, not first-time setup

.NOTPARALLEL: dns enable-unbound deploy-unbound-config deploy-unbound-local-internal \
			  deploy-unbound-service deploy-unbound-control-config \
			  dns-runtime \
			  runtime-snapshot-before runtime-snapshot-after runtime-diff \
			  wg-converge-runtime

.PHONY: \
	converge-network converge-audit \
	wg-stack wg-converge-server wg-converge-clients wg-converge-runtime \
	wg-clients-diff \
	check-forwarding network-status \
	nft-verify \
	runtime-snapshot-before runtime-snapshot-after runtime-diff

WG_CLIENTS_DRIFT   := $(INSTALL_PATH)/wg-clients-drift.sh
SNAPSHOT_NETWORK  := $(INSTALL_PATH)/snapshot-network.sh

# ------------------------------------------------------------
# Runtime snapshot locations (ephemeral, root-owned)
# ------------------------------------------------------------
RUNTIME_SNAP_BEFORE := /run/homelab-net.before
RUNTIME_SNAP_AFTER  := /run/homelab-net.after
RUNTIME_DIFF_FILE   := /tmp/homelab-net.diff

# ------------------------------------------------------------
# Top-level convergence entry points
# ------------------------------------------------------------

converge-network: check-forwarding \
				  install-homelab-sysctl \
				  nft-verify \
				  dns \
				  wg-stack
	@echo "✅ Network convergence complete"

converge-audit:
	@echo "🔍 Convergence plan (dry‑run)"
	@echo "   (audit disabled: sub-make is forbidden)"
	@echo "   Use: make -n converge-network | sed -n '1,200p'"

# ------------------------------------------------------------
# WireGuard convergence DAG
# ------------------------------------------------------------

wg-stack: wg-converge-server wg-converge-clients wg-converge-runtime

wg-converge-server: wg-deployed

wg-converge-clients: regen-clients $(WG_CLIENTS_DRIFT)
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) $(WG_CLIENTS_DRIFT) && \
		echo "♻️  Client configs already converged" || \
		echo "🔧 Client configs regenerated"

# wg-converge-runtime:
# - Detects live kernel drift
# - Never mutates state unless FORCE=1
# - Acts as a safety valve, not a default action
wg-converge-runtime: runtime-snapshot-before wg-deployed runtime-snapshot-after runtime-diff

# ------------------------------------------------------------
# Runtime drift detection (implementation detail)
# ------------------------------------------------------------
runtime-snapshot-before runtime-snapshot-after: | install-all

runtime-snapshot-before:
	@echo "📸 Capturing runtime network state (before)"
	@$(run_as_root) $(SNAPSHOT_NETWORK) "$(RUNTIME_SNAP_BEFORE)"
	@$(run_as_root) chmod 755 "$(RUNTIME_SNAP_BEFORE)"
	@$(run_as_root) chmod 644 "$(RUNTIME_SNAP_BEFORE)"/* || true

runtime-snapshot-after:
	@echo "📸 Capturing runtime network state (after)"
	@$(run_as_root) $(SNAPSHOT_NETWORK) "$(RUNTIME_SNAP_AFTER)"
	@$(run_as_root) chmod 755 "$(RUNTIME_SNAP_AFTER)"
	@$(run_as_root) chmod 644 "$(RUNTIME_SNAP_AFTER)"/* || true

# runtime-diff:
# - Pure comparison only
# - Must never mutate kernel or filesystem state (except diff marker)
runtime-diff:
	@echo "🔍 Checking runtime network state"
	@rm -f "$(RUNTIME_DIFF_FILE)"

	@diff -u "$(RUNTIME_SNAP_BEFORE)/wg.dump"  "$(RUNTIME_SNAP_AFTER)/wg.dump"  >/dev/null || echo "WG_CHANGED=1"     >>"$(RUNTIME_DIFF_FILE)"
	@diff -u "$(RUNTIME_SNAP_BEFORE)/ip.addr"  "$(RUNTIME_SNAP_AFTER)/ip.addr"  >/dev/null || echo "IP_CHANGED=1"     >>"$(RUNTIME_DIFF_FILE)"
	@diff -u "$(RUNTIME_SNAP_BEFORE)/route.v4" "$(RUNTIME_SNAP_AFTER)/route.v4" >/dev/null || echo "ROUTE4_CHANGED=1" >>"$(RUNTIME_DIFF_FILE)"
	@diff -u "$(RUNTIME_SNAP_BEFORE)/route.v6" "$(RUNTIME_SNAP_AFTER)/route.v6" >/dev/null || echo "ROUTE6_CHANGED=1" >>"$(RUNTIME_DIFF_FILE)"

	@if [ -f "$(RUNTIME_DIFF_FILE)" ]; then \
		echo "⚠️  Runtime network state requires reconciliation"; \
		sed 's/^/   - /' "$(RUNTIME_DIFF_FILE)"; \
		if [ "$(FORCE)" != "1" ]; then \
			echo ""; \
			echo "👉 Re-run with:"; \
			echo "   sudo FORCE=1 make all"; \
			exit 1; \
		fi; \
	fi
	@echo "♻️  Runtime network state already converged"

# ------------------------------------------------------------
# Client-only inspection
# ------------------------------------------------------------
wg-clients-diff:
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) $(WG_CLIENTS_DRIFT) || true

# ------------------------------------------------------------
# Infrastructure checks and status
# ------------------------------------------------------------
check-forwarding:
	@$(run_as_root) sysctl -n net.ipv4.ip_forward | grep -q '^1$$' || \
		{ echo "❌ IPv4 forwarding disabled"; exit 1; }
	@$(run_as_root) sysctl -n net.ipv6.conf.all.forwarding | grep -q '^1$$' || \
		{ echo "❌ IPv6 forwarding disabled"; exit 1; }
	@echo "♻️ Kernel forwarding already enabled"

network-status:
	@echo "🔎 Kernel forwarding"
	@$(run_as_root) sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding
	@echo
	@echo "🔎 nftables ruleset"
	@$(run_as_root) nft list table inet homelab_filter
	@$(run_as_root) nft list table ip homelab_nat

# ------------------------------------------------------------
# nftables verification
# ------------------------------------------------------------
HOMELAB_NFT_ETC_DIR   := /etc/nftables
HOMELAB_NFT_RULESET   := $(HOMELAB_NFT_ETC_DIR)/homelab.nft
HOMELAB_NFT_HASH_FILE := /var/lib/homelab/nftables.applied.sha256

nft-verify: check-forwarding
	@echo "🔍 Verifying nftables applied state"

	@if [ ! -f "$(HOMELAB_NFT_RULESET)" ]; then \
		echo "❌ nftables ruleset not present on disk"; \
		echo "   converge-network only verifies firewall state"; \
		echo "   firewall has never been applied on this host"; \
		echo ""; \
		echo "👉 First-time setup required:"; \
		echo "   sudo make nft-apply && sudo make nft-confirm"; \
		exit 1; \
	fi
	@if [ ! -f "$(HOMELAB_NFT_HASH_FILE)" ]; then \
		echo "❌ No recorded applied hash found: $(HOMELAB_NFT_HASH_FILE)"; \
		echo "👉 Firewall was never applied intentionally"; \
		echo "👉 Run: make nft-apply && make nft-confirm"; \
		exit 1; \
	fi
	@if [ ! -s "$(HOMELAB_NFT_HASH_FILE)" ]; then \
		echo "❌ Recorded nftables hash is empty"; \
		echo "👉 Run: make nft-apply && make nft-confirm"; \
		exit 1; \
	fi
	@current=$$($(run_as_root) sha256sum "$(HOMELAB_NFT_RULESET)" | awk '{print $$1}'); \
	recorded=$$($(run_as_root) cat "$(HOMELAB_NFT_HASH_FILE)"); \
	if [ "$$current" != "$$recorded" ]; then \
		echo "❌ nftables drift detected (homelab.nft changed since last apply)"; \
		echo "   Recorded: $$recorded"; \
		echo "   Current:  $$current"; \
		echo "👉 Review and run: make nft-apply && make nft-confirm"; \
		exit 1; \
	fi
	@echo "♻️  nftables ruleset matches recorded applied state"
