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
	@$(run_as_root) sh -c 'mkdir -p /run/homelab'
	@$(run_as_root) sh -c 'ssh ${SSH_OPTS} -i "${ROUTER_IDENTITY}" -p "${ROUTER_SSH_PORT}" "${SSH_USER_ROUTER}@${ROUTER_ADDR}" ip -6 addr show dev eth0 \
	| awk "/scope global/ {print \$$2}" \
	| cut -d/ -f1 \
	| sed "s/:[0-9a-fA-F]\\{1,4\\}\$$/::/" \
	| sed "s/::\\+\$$/::/" > "$(ROUTER_PREFIX_CURRENT)"'

.PHONY: prefix-bootstrap
prefix-bootstrap: router-prefix-current
	@set -e; \
	current="$$(cat "$(ROUTER_PREFIX_CURRENT)")"; \
	if ! $(run_as_root) test -f "$(STAMP_PREFIX)"; then \
		echo "📌 Prefix bootstrap: no stamp found"; \
		echo "    new: $$current"; \
		need_update=1; \
	else \
		stamped="$$( $(run_as_root) cat "$(STAMP_PREFIX)" )"; \
		if ! $(run_as_root) diff -q "$(ROUTER_PREFIX_CURRENT)" "$(STAMP_PREFIX)" >/dev/null; then \
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
		$(run_as_root) cp "$(ROUTER_PREFIX_CURRENT)" "$$tmp"; \
		$(run_as_root) mv "$$tmp" "$(STAMP_PREFIX)"; \
		$(run_as_root) touch "$(ROUTER_PREFIX_MARKER)"; \
	fi

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
	@set -euo pipefail; \
	tmpdir="$$( $(run_as_root) sh -c 'mktemp -d /run/homelab-net.before.XXXXXX' 2>/dev/null || true )"; \
	if [ -z "$$tmpdir" ]; then \
	  tmpdir="$$(mktemp -p /run -d homelab.XXXXXX)"; \
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
	  tmpdir="$$(mktemp -p /run -d homelab.XXXXXX)"; \
	fi; \
	$(run_as_root) sh -c '$(SNAPSHOT_NETWORK) "$$1"' _ "$$tmpdir"; \
	$(run_as_root) chmod 755 "$$tmpdir"; \
	$(run_as_root) chmod 644 "$$tmpdir"/* || true; \
	$(run_as_root) rm -rf "$(RUNTIME_SNAP_AFTER)" || true; \
	$(run_as_root) mv "$$tmpdir" "$(RUNTIME_SNAP_AFTER)"

# runtime-diff:
# - Pure comparison only
# - Must never mutate kernel or filesystem state (except diff marker)
runtime-diff: prefix-bootstrap
	@echo "🔍 Checking runtime network state"; \
	set -euo pipefail; \
	difffile="$$($(run_as_root) sh -c 'mktemp -p /run homelab.XXXXXX' 2>/dev/null || mktemp -p /run homelab.XXXXXX)"; \
	case "$$difffile" in /run/*) \
	  $(run_as_root) sh -c ': > "$$1" && chmod 644 "$$1"' _ "$$difffile"; \
	  trap '$(run_as_root) rm -f "$$difffile" >/dev/null 2>&1 || true' EXIT INT TERM; \
	  ;; \
	*) \
	  : >"$$difffile"; chmod 644 "$$difffile"; \
	  trap 'rm -f "$$difffile" >/dev/null 2>&1 || true' EXIT INT TERM; \
	  ;; \
	esac; \
	\
	# ------------------------------------------------------------ \
	# Compare snapshots \
	# ------------------------------------------------------------ \
	for f in wg.dump ip.addr route.v4 route.v6; do \
	  before="$(RUNTIME_SNAP_BEFORE)/$$f"; \
	  after="$(RUNTIME_SNAP_AFTER)/$$f"; \
	  if ! diff -u "$$before" "$$after" >/dev/null 2>&1; then \
		case "$$f" in \
		  wg.dump)  echo "WG_CHANGED=1"   | $(run_as_root) tee -a "$$difffile" >/dev/null ;; \
		  ip.addr)  echo "IP_CHANGED=1"   | $(run_as_root) tee -a "$$difffile" >/dev/null ;; \
		  route.v4) echo "ROUTE4_CHANGED=1" | $(run_as_root) tee -a "$$difffile" >/dev/null ;; \
		  route.v6) echo "ROUTE6_CHANGED=1" | $(run_as_root) tee -a "$$difffile" >/dev/null ;; \
		esac; \
	  fi; \
	done; \
	\
	# If no drift ➡️ done \
	if ! $(run_as_root) sh -c '[ -s "$$1" ]' _ "$$difffile"; then \
	  echo "♻️  Runtime network state already converged"; \
	  exit 0; \
	fi; \
	\
	echo "⚠️  Runtime network drift detected"; \
	$(run_as_root) sh -c 'sed "s/^/   - /" "$$1"' _ "$$difffile"; \
	\
	# ------------------------------------------------------------ \
	# Drift cause classification (non-authoritative, best-effort) \
	# ------------------------------------------------------------ \
	echo "🔍 Classifying drift cause..."; \
	cause="unknown"; \
	\
	# Case A: nftables reload or firewall re-apply \
	if $(run_as_root) sh -c 'journalctl --since "30 seconds ago" -u nftables 2>/dev/null | grep -q "Reloading"' ; then \
		cause="firewall_reload"; \
	fi; \
	\
	# Case B: sysctl reload or IPv6 token re-application \
	if $(run_as_root) sh -c 'journalctl --since "30 seconds ago" -u systemd-sysctl 2>/dev/null | grep -q "Finished Apply Kernel Variables"' ; then \
		cause="sysctl_reload"; \
	fi; \
	\
	# Case C: router-prefix-watchdog triggered a prefix check \
	if $(run_as_root) sh -c 'journalctl --since "30 seconds ago" -u router-prefix-watchdog 2>/dev/null | grep -q "prefix check"' ; then \
		cause="router_prefix_watchdog"; \
	fi; \
	\
	# Case D: interface bounced (link flap) \
	if $(run_as_root) sh -c 'journalctl --since "30 seconds ago" -k 2>/dev/null | grep -Eq "link is (up|down)"' ; then \
		cause="interface_bounce"; \
	fi; \
	\
	# Case E: headscale restart (affects routes) \
	if $(run_as_root) sh -c 'journalctl --since "30 seconds ago" -u headscale 2>/dev/null | grep -q "Started Headscale coordination server"' ; then \
		cause="headscale_restart"; \
	fi; \
	\
	# Emit classification \
	case "$${cause:-unknown}" in \
		firewall_reload)        echo "   ➡️ Cause: firewall reload (nftables)";; \
		sysctl_reload)          echo "   ➡️ Cause: sysctl reload (kernel parameters)";; \
		router_prefix_watchdog) echo "   ➡️ Cause: router-prefix-watchdog activity";; \
		interface_bounce)       echo "   ➡️ Cause: interface bounce (link flap)";; \
		headscale_restart)      echo "   ➡️ Cause: headscale restart";; \
		*)                      echo "   ➡️ Cause: unknown (no matching signals)";; \
	esac; \
	\
	# ------------------------------------------------------------ \
	# Known-safe transient drift suppression \
	# ------------------------------------------------------------ \
	continue_flag=0; \
	\
	# Extract flags \
	IP_CHANGED="$$(grep -q '^IP_CHANGED=1' "$$difffile" && echo 1 || echo 0)"; \
	ROUTE4_CHANGED="$$(grep -q '^ROUTE4_CHANGED=1' "$$difffile" && echo 1 || echo 0)"; \
	ROUTE6_CHANGED="$$(grep -q '^ROUTE6_CHANGED=1' "$$difffile" && echo 1 || echo 0)"; \
	\
	# Case 1: IP drift but final IP matches desired \
	if [ "$$IP_CHANGED" = "1" ]; then \
	  final_ip="$$(awk '/inet / {print $$2}' $(RUNTIME_SNAP_AFTER)/ip.addr | cut -d/ -f1)"; \
	  desired_ip="$$(awk '/inet / {print $$2}' $(RUNTIME_SNAP_BEFORE)/ip.addr | cut -d/ -f1)"; \
	  if [ "$$final_ip" = "$$desired_ip" ]; then \
		echo "♻️  Suppressed: transient IP drift (final state correct)"; \
		continue_flag=1; \
	  fi; \
	fi; \
	\
	# Case 2: IPv4 route drift but final route matches desired \
	if [ "$$ROUTE4_CHANGED" = "1" ]; then \
	  final_r4="$$(awk '/default/ {print $$3}' $(RUNTIME_SNAP_AFTER)/route.v4)"; \
	  desired_r4="$$(awk '/default/ {print $$3}' $(RUNTIME_SNAP_BEFORE)/route.v4)"; \
	  if [ "$$final_r4" = "$$desired_r4" ]; then \
		echo "♻️  Suppressed: transient IPv4 route drift (final state correct)"; \
		continue_flag=1; \
	  fi; \
	fi; \
	\
	# Case 3: IPv6 route drift but final route matches desired \
	if [ "$$ROUTE6_CHANGED" = "1" ]; then \
	  final_r6="$$(awk '/default/ {print $$3}' $(RUNTIME_SNAP_AFTER)/route.v6)"; \
	  desired_r6="$$(awk '/default/ {print $$3}' $(RUNTIME_SNAP_BEFORE)/route.v6)"; \
	  if [ "$$final_r6" = "$$desired_r6" ]; then \
		echo "♻️  Suppressed: transient IPv6 route drift (final state correct)"; \
		continue_flag=1; \
	  fi; \
	fi; \
	\
	# Case 4: WireGuard drift but final normalized wg.dump matches desired \
	if grep -q '^WG_CHANGED=1' "$$difffile"; then \
	tmp_before="$$(mktemp)"; \
	tmp_after="$$(mktemp)"; \
	awk '{ if (NF >= 5) { print $$1, $$2, $$3, $$4, $$5 } else { print $$0 } }' \
		"$(RUNTIME_SNAP_BEFORE)/wg.dump" > "$$tmp_before"; \
	awk '{ if (NF >= 5) { print $$1, $$2, $$3, $$4, $$5 } else { print $$0 } }' \
		"$(RUNTIME_SNAP_AFTER)/wg.dump" > "$$tmp_after"; \
	if diff -u "$$tmp_before" "$$tmp_after" >/dev/null 2>&1; then \
		echo "♻️  Suppressed: transient WireGuard drift (final state correct)"; \
		continue_flag=1; \
	fi; \
	rm -f "$$tmp_before" "$$tmp_after" >/dev/null 2>&1 || true; \
	fi; \
	\
	# If any suppression applied ➡️ skip error \
	if [ "$$continue_flag" = "1" ]; then \
	  echo "♻️  Runtime network state already converged (after suppression)"; \
	  exit 0; \
	fi; \
	\
	# ------------------------------------------------------------ \
	# Real drift ➡️ require FORCE=1 \
	# ------------------------------------------------------------ \
	if [ "$(FORCE)" != "1" ]; then \
	  echo ""; \
	  echo "➡️ Re-run with:"; \
	  echo "   sudo FORCE=1 make all"; \
	  exit 1; \
	fi; \
	\
	echo "♻️  Runtime network state converged (FORCE=1 override)"

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
	@$(run_as_root) $(SYSCTL_BIN) net.ipv4.ip_forward net.ipv6.conf.all.forwarding
	@echo
	@echo "🔍 nftables ruleset"
	@{ \
		if $(run_as_root) nft list tables | grep -q 'inet homelab_filter'; then \
			$(run_as_root) nft list table inet homelab_filter; \
		else \
			echo "❌ nftables table 'inet homelab_filter' does not exist"; \
			echo "➡️ Run: sudo make nft-apply"; \
		fi; \
		if $(run_as_root) nft list tables | grep -q 'ip homelab_nat'; then \
			$(run_as_root) nft list table ip homelab_nat; \
		else \
			echo "❌ nftables table 'ip homelab_nat' does not exist"; \
			echo "➡️ Run: sudo make nft-apply"; \
		fi; \
	}

nft-verify: check-forwarding
	@echo "🔍 Verifying nftables applied state"

	@if [ ! -f "$(HOMELAB_NFT_RULESET)" ]; then \
		echo "❌ nftables ruleset not present on disk"; \
		echo "   converge-network only verifies firewall state"; \
		echo "   firewall has never been applied on this host"; \
		echo ""; \
		echo "➡️ First-time setup required:"; \
		echo "   sudo make nft-apply && sudo make nft-confirm"; \
		exit 1; \
	fi
	@if [ ! -f "$(HOMELAB_NFT_HASH_FILE)" ]; then \
		echo "❌ No recorded applied hash found: $(HOMELAB_NFT_HASH_FILE)"; \
		echo "➡️ Firewall was never applied intentionally"; \
		echo "➡️ Run: make nft-apply && make nft-confirm"; \
		exit 1; \
	fi
	@if [ ! -s "$(HOMELAB_NFT_HASH_FILE)" ]; then \
		echo "❌ Recorded nftables hash is empty"; \
		echo "➡️ Run: make nft-apply && make nft-confirm"; \
		exit 1; \
	fi
	@current=$$($(run_as_root) sha256sum "$(HOMELAB_NFT_RULESET)" | awk '{print $$1}'); \
	recorded=$$($(run_as_root) cat "$(HOMELAB_NFT_HASH_FILE)"); \
	if [ "$$current" != "$$recorded" ]; then \
		echo "❌ nftables drift detected (homelab.nft changed since last apply)"; \
		echo "   Recorded: $$recorded"; \
		echo "   Current:  $$current"; \
		echo "➡️ Review and run: make nft-apply && make nft-confirm"; \
		exit 1; \
	fi
	@echo "♻️  nftables ruleset matches recorded applied state"
