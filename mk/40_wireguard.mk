# ============================================================
# mk/40_wireguard.mk — Essential WireGuard workflow
# - Authoritative CSV → validated compile → atomic deploy
# - No FORCE flags; failures leave last-known-good intact
# ============================================================

WG_ROOT := /volume1/homelab/wireguard
export WG_ROOT

WG_INPUT := $(WG_ROOT)/input
WG_CSV   := $(WG_INPUT)/clients.csv

SCRIPTS := $(CURDIR)/scripts

WG_COMPILE_SCRIPT := $(SCRIPTS)/wg-compile.sh
WG_KEYS_SCRIPT    := $(SCRIPTS)/wg-compile-keys.sh
WG_SERVER_KEYS_SCRIPT := $(SCRIPTS)/wg-ensure-server-keys.sh
WG_RENDER_SCRIPT  := $(SCRIPTS)/wg-compile-clients.sh
WG_EXPORT_SCRIPT  := $(SCRIPTS)/wg-client-export.sh
WG_DEPLOY_SCRIPT  := $(SCRIPTS)/wg-deploy.sh
WG_CHECK_SCRIPT   := $(SCRIPTS)/wg-check.sh
WG_SERVER_BASE_RENDER_SCRIPT := $(SCRIPTS)/wg-render-server-base.sh
WG_RENDER_CHECK_SCRIPT := $(SCRIPTS)/wg-check-render.sh

.PHONY: wg-validate wg-apply wg-render-server-base wg-compile wg-deployed wg-status wg-check \
	wg-rebuild-clean wg-rebuild-all wg-check-render

# ------------------------------------------------------------
# Compile intent → plan.tsv
# ------------------------------------------------------------
wg-compile-intent: $(WG_CSV) $(WG_COMPILE_SCRIPT)
	@test -x "$(WG_COMPILE_SCRIPT)"
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_COMPILE_SCRIPT)"


wg-ensure-server-keys: wg-compile-intent $(WG_SERVER_KEYS_SCRIPT)
	@test -x "$(WG_SERVER_KEYS_SCRIPT)"
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_SERVER_KEYS_SCRIPT)"

# ------------------------------------------------------------
# Generate client keys → keys.tsv
# ------------------------------------------------------------
wg-compile-keys: wg-compile-intent $(WG_KEYS_SCRIPT)
	@test -x "$(WG_KEYS_SCRIPT)"
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_KEYS_SCRIPT)"

# ------------------------------------------------------------
# Render client + server configs from plan.tsv + keys.tsv
# ------------------------------------------------------------
wg-render-server-base: wg-compile-intent
	@test -x "$(WG_SERVER_BASE_RENDER_SCRIPT)"
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_SERVER_BASE_RENDER_SCRIPT)"


wg-render: wg-compile-intent wg-compile-keys wg-ensure-server-keys wg-render-server-base
	@test -x "$(WG_RENDER_SCRIPT)"
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_RENDER_SCRIPT)"

# ------------------------------------------------------------
# Compile everything (no deployment)
# ------------------------------------------------------------
wg-compile: wg-compile-intent wg-compile-keys wg-render wg-check-render wg-check

# ------------------------------------------------------------
# Deploy compiled state (requires successful compile)
# ------------------------------------------------------------
wg-deployed: ensure-run-as-root net-tunnel-preflight wg-compile wg-check
	@test -x "$(WG_DEPLOY_SCRIPT)"
	@echo "🔄 WireGuard deployment requested"
	@$(run_as_root) $(WG_DEPLOY_SCRIPT)

wg-apply: wg-deployed
	@test -x "$(WG_EXPORT_SCRIPT)"
	@$(run_as_root) $(WG_EXPORT_SCRIPT)

	@echo "🔁 Reconciling WireGuard kernel state"

	@$(run_as_root) bash -euo pipefail -c '\
		: "$${WG_ROOT:?WG_ROOT not set}"; \
		PLAN="$$WG_ROOT/compiled/plan.tsv"; \
		PLAN_IFACES="$$(awk -F "\t" '\'' \
			/^#/ { next } \
			/^[[:space:]]*$$/ { next } \
			$$1=="base" && $$2=="iface" { next } \
			{ print $$2 } \
		'\'' "$$PLAN" | sort -u)"; \
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
		if [ -d "$$WG_ROOT/out/clients" ]; then \
			find "$$WG_ROOT/out/clients" -type f -name "wg*.conf" -print 2>/dev/null | while IFS= read -r conf; do \
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
			# Always converge via syncconf; wg-quick is only for first creation. \
			STRIPPED="$$(wg-quick strip "$$conf")"; \
			if ! ip link show "$$iface" >/dev/null 2>&1; then \
				# Create empty kernel interface (no routes/rules side-effects). \
				ip link add "$$iface" type wireguard; \
			fi; \
			# Apply WireGuard config (keys/peers) idempotently. \
			printf "%s\n" "$$STRIPPED" | wg setconf "$$iface" /dev/fd/0; \
			# Converge MTU (wg-quick used to do this). \
			ip link set mtu 1420 dev "$$iface" 2>/dev/null || true; \
			# Ensure link is up. \
			ip link set up dev "$$iface" 2>/dev/null || true; \
			# Converge addresses (no duplicate-add failures). \
			ADDRS="$$(sed -n '\''s/^[[:space:]]*Address[[:space:]]*=[[:space:]]*//p'\'' "$$conf" \
				| tr ",\n" "  " \
				| awk '\''{ for (i=1;i<=NF;i++) print $$i }'\'')"; \
			if [ -n "$$ADDRS" ]; then \
				for cidr in $$ADDRS; do \
					ip_only="$${cidr%/*}"; \
					owner="$$(ip -o addr show | awk -v ip="$$ip_only" '\''{ split($$4,a,"/"); if (a[1]==ip) { print $$2; exit } }'\'')"; \
					[ -z "$$owner" -o "$$owner" = "$$iface" ] || { \
						echo "wg-apply: ERROR: $$ip_only already assigned on interface $$owner (cannot bring up $$iface)" >&2; \
						exit 1; \
					}; \
					ip addr replace "$$cidr" dev "$$iface"; \
				done; \
			fi; \
		done \
	'

	@echo "✅ WireGuard kernel state converged"

# ------------------------------------------------------------
# Consistency / sanity checks
# ------------------------------------------------------------
wg-check: ensure-run-as-root
	@test -x "$(WG_CHECK_SCRIPT)"
	@$(run_as_root) $(WG_CHECK_SCRIPT)

wg-rebuild-clean: ensure-run-as-root
	@echo "🔥 FULL WireGuard rebuild (keys + config)"
	@echo "⚠️  This will invalidate ALL existing clients"
	@echo "⚠️  Press Ctrl-C now if this is not intended"
	@sleep 5
	@echo "▶ recording compromised WireGuard keys"
	@$(run_as_root) $(SCRIPTS)/wg-record-compromised-keys.sh
	@echo "▶ destroying existing WireGuard state"
	@$(run_as_root) $(SCRIPTS)/wg-nuke.sh

wg-rebuild-all: wg-rebuild-clean wg-apply
	@echo "🔥 WireGuard fully rebuilt with fresh keys"

wg-check-render: wg-render
	@test -x "$(WG_RENDER_CHECK_SCRIPT)"
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_RENDER_CHECK_SCRIPT)"
