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
	wg-stack wg-converge-clients wg-converge-runtime \
	wg-clients-diff \
	check-forwarding network-status \
	nft-verify \
	runtime-snapshot-before runtime-snapshot-after runtime-diff

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
	@echo "🔍 Convergence plan (dry-run)"
	@echo "   (audit disabled: sub-make is forbidden)"
	@echo "   Use: make -n converge-network | sed -n '1,200p'"

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
	@set -euo pipefail; \
	tmpdir="$$( $(run_as_root) sh -c 'mktemp -d /run/homelab-net.before.XXXXXX' 2>/dev/null || true )"; \
	if [ -z "$$tmpdir" ]; then \
	  tmpdir="$$(mktemp -d)"; \
	fi; \
	$(run_as_root) sh -c '$(SNAPSHOT_NETWORK) "$$1"' _ "$$tmpdir"; \
	$(run_as_root) chmod 755 "$$tmpdir"; \
	$(run_as_root) chmod 644 "$$tmpdir"/* || true; \
	$(run_as_root) rm -rf "$(RUNTIME_SNAP_BEFORE)" || true; \
	$(run_as_root) mv "$$tmpdir" "$(RUNTIME_SNAP_BEFORE)"

runtime-snapshot-after:
	@echo "📸 Capturing runtime network state (after)"
	@set -euo pipefail; \
	tmpdir="$$( $(run_as_root) sh -c 'mktemp -d /run/homelab-net.after.XXXXXX' 2>/dev/null || true )"; \
	if [ -z "$$tmpdir" ]; then \
	  tmpdir="$$(mktemp -d)"; \
	fi; \
	$(run_as_root) sh -c '$(SNAPSHOT_NETWORK) "$$1"' _ "$$tmpdir"; \
	$(run_as_root) chmod 755 "$$tmpdir"; \
	$(run_as_root) chmod 644 "$$tmpdir"/* || true; \
	$(run_as_root) rm -rf "$(RUNTIME_SNAP_AFTER)" || true; \
	$(run_as_root) mv "$$tmpdir" "$(RUNTIME_SNAP_AFTER)"


# runtime-diff:
# - Pure comparison only
# - Must never mutate kernel or filesystem state (except diff marker)
runtime-diff:
	@echo "🔍 Checking runtime network state"; \
	set -euo pipefail; \
	difffile="$$($(run_as_root) sh -c 'mktemp /run/homelab-net.diff.XXXXXX' 2>/dev/null || mktemp)"; \
	case "$$difffile" in /run/*) \
	  $(run_as_root) sh -c ': > "$$1" && chmod 644 "$$1"' _ "$$difffile"; \
	  trap '$(run_as_root) rm -f "$$difffile" >/dev/null 2>&1 || true' EXIT INT TERM; \
	  ;; \
	*) \
	  : >"$$difffile"; chmod 644 "$$difffile"; \
	  trap 'rm -f "$$difffile" >/dev/null 2>&1 || true' EXIT INT TERM; \
	  ;; \
	esac; \
	for f in wg.dump ip.addr route.v4 route.v6; do \
	  before="$(RUNTIME_SNAP_BEFORE)/$$f"; \
	  after="$(RUNTIME_SNAP_AFTER)/$$f"; \
	  if ! diff -u "$$before" "$$after" >/dev/null 2>&1; then \
		case "$$f" in \
		  wg.dump) $(run_as_root) sh -c 'echo "WG_CHANGED=1" >> "$$1"' _ "$$difffile" ;; \
		  ip.addr) $(run_as_root) sh -c 'echo "IP_CHANGED=1" >> "$$1"' _ "$$difffile" ;; \
		  route.v4) $(run_as_root) sh -c 'echo "ROUTE4_CHANGED=1" >> "$$1"' _ "$$difffile" ;; \
		  route.v6) $(run_as_root) sh -c 'echo "ROUTE6_CHANGED=1" >> "$$1"' _ "$$difffile" ;; \
		esac; \
	  fi; \
	done; \
	if $(run_as_root) sh -c '[ -s "$$1" ]' _ "$$difffile"; then \
	  echo "⚠️  Runtime network state requires reconciliation"; \
	  $(run_as_root) sh -c 'sed "s/^/   - /" "$$1"' _ "$$difffile"; \
	  if [ "$(FORCE)" != "1" ]; then \
		echo ""; \
		echo "👉 Re-run with:"; \
		echo "   sudo FORCE=1 make all"; \
		exit 1; \
	  fi; \
	fi; \
	$(run_as_root) rm -f "$$difffile" >/dev/null 2>&1 || rm -f "$$difffile" >/dev/null 2>&1; \
	echo "♻️  Runtime network state already converged"




# ------------------------------------------------------------
# Infrastructure checks and status
# ------------------------------------------------------------
check-forwarding:
	@set -euo pipefail; \
	out="$$($(run_as_root) sh -c 'echo $$(cat /proc/sys/net/ipv4/ip_forward /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null) || echo "0 0"')"; \
	set -- $$out; \
	v4="$${1:-0}"; v6="$${2:-0}"; \
	if [ "$$v4" != "1" ] || [ "$$v6" != "1" ]; then \
		[ "$$v4" != "1" ] && echo "❌ IPv4 forwarding disabled ($$v4)"; \
		[ "$$v6" != "1" ] && echo "❌ IPv6 forwarding disabled ($$v6)"; \
		exit 1; \
	fi; \
	echo "♻️ Kernel forwarding already enabled"

.PHONY: converge-forwarding
converge-forwarding:
	@set -euo pipefail; \
	out="$$($(run_as_root) sh -c 'echo $$(cat /proc/sys/net/ipv4/ip_forward /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null) || echo "0 0"')"; \
	set -- $$out; \
	v4="$${1:-0}"; v6="$${2:-0}"; \
	if [ "$$v4" != "1" ] || [ "$$v6" != "1" ]; then \
		echo "🔧 Forwarding out of spec (v4:$$v4, v6:$$v6). Applying fix..."; \
		$(run_as_root) sh -c 'echo 1 > /proc/sys/net/ipv4/ip_forward; echo 1 > /proc/sys/net/ipv6/conf/all/forwarding' || { echo "❌ Failed to set kernel parameters"; exit 1; }; \
		out="$$($(run_as_root) sh -c "echo \$$(cat /proc/sys/net/ipv4/ip_forward /proc/sys/net/ipv6/conf/all/forwarding)")"; \
		set -- $$out; \
		if [ "$${1:-0}" != "1" ] || [ "$${2:-0}" != "1" ]; then echo "❌ Verification failed after fix"; exit 1; fi; \
		echo "✅ Forwarding enabled and verified"; \
	else \
		echo "♻️ Kernel forwarding already enabled"; \
	fi

network-status:
	@echo "🔍 Kernel forwarding"
	@$(run_as_root) sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding
	@echo
	@echo "🔍 nftables ruleset"
	@{ \
		if $(run_as_root) nft list tables | grep -q 'inet homelab_filter'; then \
			$(run_as_root) nft list table inet homelab_filter; \
		else \
			echo "❌ nftables table 'inet homelab_filter' does not exist"; \
			echo "👉 Run: sudo make nft-apply"; \
		fi; \
		if $(run_as_root) nft list tables | grep -q 'ip homelab_nat'; then \
			$(run_as_root) nft list table ip homelab_nat; \
		else \
			echo "❌ nftables table 'ip homelab_nat' does not exist"; \
			echo "👉 Run: sudo make nft-apply"; \
		fi; \
	}

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
