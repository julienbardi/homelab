# ============================================================
# mk/90_converge.mk — Explicit network convergence (safe by default)
# ============================================================
# NOTE:
# - converge-network verifies and reconciles network state
# - Safe by default: no live mutation without FORCE=1
# - Intended for steady-state convergence, not first-time setup

# --- Canonical router SSH (authoritative, non‑drifting) ---
: "${SSH_USER_ROUTER:?SSH_USER_ROUTER required}"
: "${ROUTER_ADDR:?ROUTER_ADDR required}"
: "${ROUTER_SSH_PORT:=2222}"
: "${SSH_OPTS:=-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes}"
: "${ROUTER_IDENTITY:=$HOME/.ssh/id_ed25519}"

.NOTPARALLEL: dns enable-unbound deploy-unbound-config deploy-unbound-local-internal \
			  deploy-unbound-service \
			  dns-runtime \
			  runtime-snapshot-before runtime-snapshot-after runtime-diff \
			  wg-converge-runtime \
			  converge-network

.PHONY: \
	converge-network converge-audit \
	wg-stack wg-converge-clients wg-converge-runtime \
	wg-clients-diff \
	check-forwarding network-status \
	nft-verify \
	runtime-snapshot-before runtime-snapshot-after runtime-diff

SNAPSHOT_NETWORK  := $(INSTALL_PATH)/snapshot-network.sh

ROUTER_PREFIX_CURRENT := /run/homelab/router-prefix.current
STAMP_PREFIX := $(STAMP_DIR_ROOT)/router-prefix.last

router-prefix-current:
	@$(run_as_root) sh -c 'mkdir -p /run/homelab && \
		ssh ${SSH_OPTS} -i "${ROUTER_IDENTITY}" -p "${ROUTER_SSH_PORT}" "${SSH_USER_ROUTER}@${ROUTER_ADDR}" ip -6 addr show dev eth0 \
		| awk "/scope global/ {print \$$2}" \
		| cut -d/ -f1 \
		| sed "s/:[0-9a-fA-F]\\{1,4\\}\$$/::/" \
		| sed "s/::\\+\$$/::/" > "$(ROUTER_PREFIX_CURRENT)"'

.PHONY: prefix-bootstrap
prefix-bootstrap: router-prefix-current
	@$(run_as_root) sh -c 'set -e; \
		current="$$(cat "$(ROUTER_PREFIX_CURRENT)")"; \
		if ! test -f "$(STAMP_PREFIX)"; then \
			echo "📌 Prefix bootstrap: no stamp found"; \
			echo "    new: $$current"; \
			need_update=1; \
		else \
			stamped="$$(cat "$(STAMP_PREFIX)")"; \
			if ! diff -q "$(ROUTER_PREFIX_CURRENT)" "$(STAMP_PREFIX)" >/dev/null; then \
				echo "📌 Prefix changed — updating stamp"; \
				echo "    old: $$stamped"; \
				echo "    new: $$current"; \
				need_update=1; \
			else \
				echo "📌 Prefix already converged: $$current"; \
				need_update=0; \
			fi; \
		fi; \
		if [ "$$need_update" -eq 1 ]; then \
			tmp="$(STAMP_DIR_ROOT)/tmp.router-prefix"; \
			cp "$(ROUTER_PREFIX_CURRENT)" "$$tmp"; \
			mv "$$tmp" "$(STAMP_PREFIX)"; \
			touch "$(ROUTER_PREFIX_MARKER)"; \
		fi'

# ------------------------------------------------------------
# Runtime snapshot locations (ephemeral, root-owned)
# ------------------------------------------------------------
RUNTIME_SNAP_BEFORE := /run/homelab-net.before
RUNTIME_SNAP_AFTER  := /run/homelab-net.after
RUNTIME_DIFF_FILE   := /run/homelab-net.diff

# ------------------------------------------------------------
# Top-level convergence entry points
# ------------------------------------------------------------

converge-network: check-forwarding \
				  install-homelab-sysctl \
				  ensure-accept-ra \
				  nft-verify \
				  ensure-default-route \
				  wg-stack
	@echo "✅ Network convergence complete"

.PHONY: converge-router-prefix
converge-router-prefix: $(STAMP_DIR_ROOT) router-converge $(ROUTER_PREFIX_MARKER)
	@echo "🌐 Router prefix changed — router DAG converged"
	@rm -f $(ROUTER_PREFIX_MARKER)
	@echo " Marker consumed"

# ------------------------------------------------------------
# WireGuard convergence DAG
# ------------------------------------------------------------

wg-stack: wg-converge-clients wg-converge-runtime

# wg-converge-runtime:
# - Detects live kernel drift
# - Never mutates state unless FORCE=1
# - Acts as a safety valve, not a default action
wg-converge-runtime: runtime-snapshot-before runtime-snapshot-after runtime-diff

# ------------------------------------------------------------
# Runtime drift detection (implementation detail)
# ------------------------------------------------------------
runtime-snapshot-before runtime-snapshot-after: | install-all

runtime-snapshot-before:
	@echo "📸 Capturing runtime network state (before)"
	@$(run_as_root) sh -c 'set -euo pipefail; \
		tmpdir="$$(mktemp -d /run/homelab-net.before.XXXXXX 2>/dev/null || true)"; \
		if [ -z "$$tmpdir" ]; then \
			tmpdir="$$(mktemp -p /run -d homelab.XXXXXX)"; \
		fi; \
		"$(SNAPSHOT_NETWORK)" "$$tmpdir"; \
		chmod 755 "$$tmpdir"; \
		chmod 644 "$$tmpdir"/* || true; \
		rm -rf "$(RUNTIME_SNAP_BEFORE)" || true; \
		mv "$$tmpdir" "$(RUNTIME_SNAP_BEFORE)"'

runtime-snapshot-after:
	@echo "📸 Capturing runtime network state (after)"
	@$(run_as_root) sh -c 'set -euo pipefail; \
		tmpdir="$$(mktemp -d /run/homelab-net.after.XXXXXX 2>/dev/null || true)"; \
		if [ -z "$$tmpdir" ]; then \
			tmpdir="$$(mktemp -p /run -d homelab.XXXXXX)"; \
		fi; \
		"$(SNAPSHOT_NETWORK)" "$$tmpdir"; \
		chmod 755 "$$tmpdir"; \
		chmod 644 "$$tmpdir"/* || true; \
		rm -rf "$(RUNTIME_SNAP_AFTER)" || true; \
		mv "$$tmpdir" "$(RUNTIME_SNAP_AFTER)"'

# runtime-diff:
# - Pure comparison only
# - Must never mutate kernel or filesystem state (except diff marker)
runtime-diff: prefix-bootstrap install-all
	@$(run_as_root) $(INSTALL_PATH)/runtime-diff.sh "$(RUNTIME_SNAP_BEFORE)" "$(RUNTIME_SNAP_AFTER)"

# ------------------------------------------------------------
# Infrastructure checks and status
# ------------------------------------------------------------
check-forwarding:
	@$(run_as_root) sh -c 'set -euo pipefail; \
		out="$$(echo $$(cat /proc/sys/net/ipv4/ip_forward /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null) || echo "0 0")"; \
		set -- $$out; \
		v4="$${1:-0}"; v6="$${2:-0}"; \
		if [ "$$v4" != "1" ] || [ "$$v6" != "1" ]; then \
			[ "$$v4" != "1" ] && echo "❌ IPv4 forwarding disabled ($$v4)"; \
			[ "$$v6" != "1" ] && echo "❌ IPv6 forwarding disabled ($$v6)"; \
			exit 1; \
		fi; \
		echo "♻️ Kernel forwarding already enabled"'

.PHONY: converge-forwarding
converge-forwarding:
	@$(run_as_root) sh -c 'set -euo pipefail; \
		out="$$(echo $$(cat /proc/sys/net/ipv4/ip_forward /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null) || echo "0 0")"; \
		set -- $$out; \
		v4="$${1:-0}"; v6="$${2:-0}"; \
		if [ "$$v4" != "1" ] || [ "$$v6" != "1" ]; then \
			echo "🔧 Forwarding out of spec (v4:$$v4, v6:$$v6). Applying fix..."; \
			echo 1 > /proc/sys/net/ipv4/ip_forward; echo 1 > /proc/sys/net/ipv6/conf/all/forwarding; \
			out="$$(echo $$(cat /proc/sys/net/ipv4/ip_forward /proc/sys/net/ipv6/conf/all/forwarding))"; \
			set -- $$out; \
			if [ "$${1:-0}" != "1" ] || [ "$${2:-0}" != "1" ]; then echo "❌ Verification failed after fix"; exit 1; fi; \
			echo "✅ Forwarding enabled and verified"; \
		else \
			echo "♻️ Kernel forwarding already enabled"; \
		fi'

network-status:
	@echo "🔍 Kernel forwarding"
	@$(run_as_root) $(SYSCTL_BIN) net.ipv4.ip_forward net.ipv6.conf.all.forwarding
	@echo
	@echo "🔍 nftables ruleset"
	@$(run_as_root) sh -c ' \
		if nft list tables | grep -q "inet homelab_filter"; then \
			nft list table inet homelab_filter; \
		else \
			echo "❌ nftables table 'inet homelab_filter' does not exist"; \
			echo "➡️ Run: sudo make nft-apply"; \
		fi; \
		if nft list tables | grep -q "ip homelab_nat"; then \
			nft list table ip homelab_nat; \
		else \
			echo "❌ nftables table 'ip homelab_nat' does not exist"; \
			echo "➡️ Run: sudo make nft-apply"; \
		fi'

nft-verify: check-forwarding
	@echo "🔍 Verifying nftables applied state"
	@$(run_as_root) sh -c 'set -euo pipefail; \
		if [ ! -f "$(HOMELAB_NFT_RULESET)" ]; then \
			echo "❌ nftables ruleset not present on disk"; \
			echo "   converge-network only verifies firewall state"; \
			echo "   firewall has never been applied on this host"; \
			echo ""; \
			echo "➡️ First-time setup required:"; \
			echo "   sudo make nft-apply && sudo make nft-confirm"; \
			exit 1; \
		fi; \
		if [ ! -f "$(HOMELAB_NFT_HASH_FILE)" ]; then \
			echo "❌ No recorded applied hash found: $(HOMELAB_NFT_HASH_FILE)"; \
			echo "➡️ Firewall was never applied intentionally"; \
			echo "➡️ Run: make nft-apply && make nft-confirm"; \
			exit 1; \
		fi; \
		if [ ! -s "$(HOMELAB_NFT_HASH_FILE)" ]; then \
			echo "❌ Recorded nftables hash is empty"; \
			echo "➡️ Run: make nft-apply && make nft-confirm"; \
			exit 1; \
		fi; \
		current="$$(sha256sum "$(HOMELAB_NFT_RULESET)" | awk "{print \$$1}")"; \
		recorded="$$(cat "$(HOMELAB_NFT_HASH_FILE)")"; \
		if [ "$$current" != "$$recorded" ]; then \
			echo "❌ nftables drift detected (homelab.nft changed since last apply)"; \
			echo "   Recorded: $$recorded"; \
			echo "   Current:  $$current"; \
			echo "➡️ Review and run: make nft-apply && make nft-confirm"; \
			exit 1; \
		fi; \
		echo "♻️  nftables ruleset matches recorded applied state"'