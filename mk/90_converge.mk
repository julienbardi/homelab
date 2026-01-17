# ============================================================
# mk/90_converge.mk — Explicit network convergence (safe by default)
#
# Convergence semantics:
# - Verifies kernel forwarding and firewall integrity
# - Applies idempotent server WireGuard state (no mutation)
# - Detects client configuration drift and shows diffs
# - Requires explicit FORCE=1 only when mutation would occur:
#     * client regeneration
#     * runtime peer reconciliation
#
# Safety guarantees:
# - No WireGuard state is modified without explicit confirmation
# - Client drift is always shown before FORCE is requested
# - Runtime changes are gated behind FORCE
#
# Usage:
#   sudo make all              # Safe unless drift is detected
#   sudo FORCE=1 make all      # Apply all required changes
#   make wg-clients-diff       # Inspect client drift only (no mutation)
#
# Keeps bin/run-as-root unchanged (argv tokens contract).
# NOTE:
# Output must be deterministic.
# Do NOT add timestamps or run-specific metadata.
# Drift detection relies on byte-stable output.
# ============================================================
.PHONY: converge-network converge-audit \
		check-force check-forwarding \
		wg-stack network-status \
		wg-converge-server wg-converge-clients wg-converge-runtime

converge-network: check-forwarding \
				  install-homelab-sysctl \
				  nft-verify \
				  dns-runtime \
				  wg-stack
	@echo "✅ Network convergence complete"

converge-audit:
	@echo "🔎 Converge DAG (what would run)"
	@echo "   (audit disabled: sub-make is forbidden)"
	@echo "   Use: make -n converge-network | sed -n '1,200p'"

check-force:
	@if echo "$(MAKEFLAGS)" | grep -q -- '-n'; then \
		echo "[audit] FORCE check skipped"; \
	elif [ "$(FORCE)" != "1" ]; then \
		echo "ERROR: a sub‑step detected drift"; \
		echo "       converge-network rewrites WireGuard state"; \
		echo "       explicit confirmation required"; \
		echo ""; \
		echo "👉 Re-run with:"; \
		echo "   sudo FORCE=1 make all"; \
		exit 1; \
	fi

.PHONY: wg-clients-diff
wg-clients-diff:
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(HOMELAB_DIR)/scripts/wg-clients-drift.sh" || true

.PHONY: wg-stack
wg-stack: wg-converge-server wg-converge-clients wg-converge-runtime

wg-converge-server: wg-deployed

wg-converge-clients: regen-clients
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(HOMELAB_DIR)/scripts/wg-clients-drift.sh" && \
		echo "✅ Client configs already converged" || \
		echo "🔁 Client configs regenerated"

wg-converge-runtime: check-force wg-deployed

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

HOMELAB_NFT_ETC_DIR   := /etc/nftables
HOMELAB_NFT_RULESET   := $(HOMELAB_NFT_ETC_DIR)/homelab.nft
HOMELAB_NFT_HASH_FILE := /var/lib/homelab/nftables.applied.sha256

.PHONY: nft-verify
nft-verify: check-forwarding
	@echo "🔍 [make] Verifying homelab nftables applied hash"

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

	@echo "✅ [make] nftables ruleset matches recorded applied state"

