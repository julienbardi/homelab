# mk/42_wireguard_runtime.mk
WG_ROUTER_SUBNET_V4 = $(shell WG_ROOT="$(WG_ROOT)" $(WG_PLAN_SUBNETS) --router --v4 | awk 'NR==1 {print $$2}')
WG_ROUTER_SUBNET_V6 = $(shell WG_ROOT="$(WG_ROOT)" $(WG_PLAN_SUBNETS) --router --v6 | awk 'NR==1 {print $$2}')

wg-prepare: wg-install-scripts wg-compile wg-check
wg-runtime: require-wg-plan-subnets wg-install-scripts ensure-run-as-root wg-check wg-apply-verified

# ------------------------------------------------------------
# Consistency & Verification
# ------------------------------------------------------------
wg-check: wg-install-scripts ensure-run-as-root
	@test -f "$(WG_ROOT)/compiled/plan.tsv" || { echo "❌ missing plan: $(WG_ROOT)/compiled/plan.tsv (run: make wg-prepare)"; exit 1; }
	@$(run_as_root) $(WG_CHECK_SCRIPT) $(WG_ROOT)/compiled/plan.tsv

wg-check-render: wg-install-scripts wg-render-missing
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_RENDER_CHECK_SCRIPT)"

wg-verify-no-key-reuse: wg-install-scripts ensure-run-as-root
	@$(run_as_root) bash -euo pipefail -c '\
		echo "🔍 Verifying no WireGuard key reuse against compromised ledger"; \
		ledger="$(SECURITY_DIR)/compromised_keys.tsv"; \
		tmp="$$(mktemp)"; \
		trap "rm -f '\''$$tmp'\''" EXIT; \
		\
		wg show | awk '\''/^interface: /{iface=$$2} /^  public key: /{print iface "\t" $$3}'\'' \
		| while IFS=$$'\''\t'\'' read -r iface pub; do \
			fp="$$(printf "%s" "$$pub" | sha256sum | awk '\''{print $$1}'\'')"; \
			printf "%s\tSHA256:%s\n" "$$iface" "$$fp"; \
		done >"$$tmp"; \
		\
		if awk -F"\t" '\''{print $$2}'\'' "$$tmp" | grep -Fxf - "$$ledger" >/dev/null; then \
			echo "❌ REUSED KEY DETECTED (active key intersects compromised ledger)"; \
			exit 1; \
		fi; \
		echo "✅ No compromised keys in active WireGuard state"; \
	'

wg-verify-no-legacy-keys: wg-install-scripts ensure-run-as-root
	@test ! -d /etc/wireguard/.legacy || { \
		echo "❌ ERROR: legacy WireGuard key directory exists (/etc/wireguard/.legacy)"; \
		exit 1; \
	}

# ------------------------------------------------------------
# Maintenance & Destruction
# ------------------------------------------------------------
wg-rebuild-clean: wg-install-scripts ensure-run-as-root
	@echo "🔥 FULL WireGuard rebuild (keys + config)"
	@sleep 5
	@$(run_as_root) $(WG_RECORD_COMPROMISED_KEYS_SCRIPT)

wg-rebuild-guard:
	@if [ "$(FORCE)" != "1" ]; then echo "❌ wg-rebuild-all is destructive. Re-run with FORCE=1"; exit 1; fi

wg-rebuild-all: wg-rebuild-guard wg-install-scripts wg-rebuild-clean wg-ensure-server-keys wg-apply-verified
	@echo "🔥 WireGuard fully rebuilt with fresh keys"

wg-rotate-client: wg-install-scripts ensure-run-as-root
	@if [ -z "$(base)" ] || [ -z "$(iface)" ]; then echo "Usage: make wg-rotate-client base=<base> iface=<iface>"; exit 1; fi
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_ROTATE_CLIENT)" "$(base)" "$(iface)"

wg-remove-client: wg-install-scripts ensure-run-as-root
	@if [ -z "$(base)" ] || [ -z "$(iface)" ]; then echo "Usage: make wg-remove-client base=<base> iface=<iface>"; exit 1; fi
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_REMOVE_CLIENT)" "$(base)" "$(iface)"

wg: wg-prepare wg-runtime

# ------------------------------------------------------------
# Compilation & Rendering
# ------------------------------------------------------------
wg-compile-intent: wg-install-scripts wg-clean-out
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_COMPILE_SCRIPT)"

wg-ensure-server-keys: wg-install-scripts wg-compile-intent
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_SERVER_KEYS_SCRIPT)" \
		|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]

wg-compile-keys: wg-install-scripts wg-compile-intent
	@$(run_as_root) env WG_ROOT="$(WG_ROOT)" WG_PHASE=compile "$(WG_KEYS_SCRIPT)"

wg-render-server-base: wg-install-scripts wg-ensure-server-keys
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_SERVER_BASE_RENDER_SCRIPT)"

wg-render: wg-install-scripts wg-compile-intent wg-compile-keys wg-render-server-base
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_RENDER_SCRIPT)"
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_CHECK_RENDERED_SCRIPT)"

wg-render-missing: wg-install-scripts wg-compile-intent wg-compile-keys wg-render-server-base
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_RENDER_MISSING_SCRIPT)"

$(WG_ROOT)/compiled/plan.tsv: wg-compile-intent

wg-compile: wg-install-scripts wg-compile-intent wg-compile-keys wg-render-missing wg-check-render wg-check

# ------------------------------------------------------------
# Deployment & Kernel State Sync
# ------------------------------------------------------------
wg-deployed: wg-install-scripts ensure-run-as-root net-tunnel-preflight firewall-nas wg-check
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🔄 WireGuard deployment requested"; fi
	@$(run_as_root) $(WG_DEPLOY_SCRIPT)

wg-apply-verified: wg-apply wg-verify-no-key-reuse wg-verify-no-legacy-keys

wg-apply: wg-install-scripts wg-deployed
	@$(run_as_root) env \
		PLAN="$(WG_ROOT)/compiled/plan.tsv" \
		PLAN_READER="$(INSTALL_PATH)/wg-plan-read.sh" \
		$(WG_EXPORT_SCRIPT)

	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🔁 Reconciling WireGuard kernel state"; fi

	@$(run_as_root) bash -euo pipefail -c '\
		: "$${WG_ROOT:?WG_ROOT not set}"; \
		PLAN="$$WG_ROOT/compiled/plan.tsv"; \
		PLAN_IFACES="$$( $(INSTALL_PATH)/wg-plan-read.sh "$$PLAN" | awk -F "\t" '\''{ print $$2 }'\'' | sort -u )"; \
	\
		for iface in $$(wg show interfaces 2>/dev/null || true); do \
			case "$$iface" in wg[0-9]|wg1[0-5]) ;; *) continue ;; esac; \
			echo "$$PLAN_IFACES" | grep -qx "$$iface" || { \
				echo "🧹 wg-apply: tearing down stale interface $$iface"; \
				wg-quick down "$$iface" || true; \
			}; \
		done; \
	\
		for conf in /etc/wireguard/wg*.conf; do \
			[ -e "$$conf" ] || continue; \
			iface="$$(basename "$$conf" .conf)"; \
			case "$$iface" in wg[0-9]|wg1[0-5]) ;; *) continue ;; esac; \
			echo "$$PLAN_IFACES" | grep -qx "$$iface" || { \
				echo "🧹 wg-apply: removing stale server config $$conf"; \
				rm -f "$$conf"; \
			}; \
		done; \
	\
		if [ -d "$$WG_ROOT/export/clients" ]; then \
			find "$$WG_ROOT/export/clients" -type f -name "wg*.conf" -print 2>/dev/null | while IFS= read -r conf; do \
				[ -e "$$conf" ] || continue; \
				iface="$$(basename "$$conf" .conf)"; \
				case "$$iface" in wg[0-9]|wg1[0-5]) ;; *) continue ;; esac; \
				echo "$$PLAN_IFACES" | grep -qx "$$iface" || { \
					echo "🧹 wg-apply: removing stale client config $$conf"; \
					rm -f "$$conf"; \
				}; \
			done; \
		fi; \
	\
	for iface in $$PLAN_IFACES; do \
		conf="/etc/wireguard/$${iface}.conf"; \
		[ -f "$$conf" ] || { echo "wg-apply: ERROR: missing $$conf" >&2; exit 1; }; \
		grep -qE '\''^[[:space:]]*Address[[:space:]]*='\'' "$$conf" || { \
			echo "wg-apply: ERROR: $$conf missing Address= (refusing to bring up $$iface)" >&2; \
			exit 1; \
		}; \
		grep -qE '\''^[[:space:]]*ListenPort[[:space:]]*='\'' "$$conf" || { \
			echo "wg-apply: ERROR: $$conf missing ListenPort= (refusing to bring up $$iface)" >&2; \
			exit 1; \
		}; \
		if ! ip link show "$$iface" >/dev/null 2>&1; then \
			wg-quick up "$$iface" >/dev/null; \
		else \
			wg syncconf "$$iface" <(wg-quick strip "$$conf"); \
		fi; \
		ip link set mtu 1420 dev "$$iface" 2>/dev/null || true; \
		ip link set up dev "$$iface" 2>/dev/null || true; \
		if ! ip route show dev "$$iface" | grep -q . && ! ip -6 route show dev "$$iface" | grep -q .; then \
			echo "wg-apply: ERROR: $$iface has no routes (v4 or v6)" >&2; \
			exit 1; \
		fi; \
	done; \
	'
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "✅ WireGuard kernel state converged"; fi

wg-seed-keys: wg-install-scripts wg-compile-intent
	@echo "⚠️  Explicit key seeding requested"
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_SEED_KEYS_SCRIPT)"
