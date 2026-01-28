# ============================================================
# mk/40_wireguard.mk — Essential WireGuard workflow
# - Authoritative CSV → validated compile → atomic deploy
# - All paths anchored to mk/00_constants.mk
# ============================================================

WG_INPUT := $(WG_ROOT)/input
WG_CSV   := $(WG_INPUT)/clients.csv

WG_COMPILE_SCRIPT := $(INSTALL_PATH)/wg-compile.sh
WG_KEYS_SCRIPT    := $(INSTALL_PATH)/wg-compile-keys.sh
WG_SERVER_KEYS_SCRIPT := $(INSTALL_PATH)/wg-ensure-server-keys.sh
WG_RENDER_SCRIPT  := $(INSTALL_PATH)/wg-compile-clients.sh
WG_RENDER_MISSING_SCRIPT := $(INSTALL_PATH)/wg-render-missing-clients.sh
WG_EXPORT_SCRIPT  := $(INSTALL_PATH)/wg-client-export.sh
WG_DEPLOY_SCRIPT  := $(INSTALL_PATH)/wg-deploy.sh
WG_CHECK_SCRIPT   := $(INSTALL_PATH)/wg-check.sh
WG_SERVER_BASE_RENDER_SCRIPT := $(INSTALL_PATH)/wg-render-server-base.sh
WG_RENDER_CHECK_SCRIPT := $(INSTALL_PATH)/wg-check-render.sh
WG_RECORD_COMPROMISED_KEYS_SCRIPT := $(INSTALL_PATH)/wg-record-compromised-keys.sh
WG_REMOVE_CLIENT := $(INSTALL_PATH)/wg-remove-client.sh
WG_ROTATE_CLIENT := $(INSTALL_PATH)/wg-rotate-client.sh

# No need to export WG_ROOT here
# It is already exported globally by mk/00_constants.mk

.PHONY: wg-install-scripts \
	wg-clean-out \
	wg-compile-intent \
	wg-ensure-server-keys \
	wg-compile-keys \
	wg-render-server-base \
	wg-render \
	wg-render-missing \
	wg-compile \
	wg-deployed \
	wg-apply \
	wg-apply-verified \
	wg-check \
	wg-check-render \
	wg-rebuild-clean \
	wg-verify-no-key-reuse \
	wg-verify-no-legacy-keys \
	wg-rebuild-guard \
	wg-rebuild-all \
	wg \
	wg-rotate-client \
	wg-remove-client

wg-install-scripts: ensure-run-as-root \
	$(WG_COMPILE_SCRIPT) \
	$(WG_KEYS_SCRIPT) \
	$(WG_SERVER_KEYS_SCRIPT) \
	$(WG_RENDER_SCRIPT) \
	$(WG_RENDER_MISSING_SCRIPT) \
	$(WG_EXPORT_SCRIPT) \
	$(WG_DEPLOY_SCRIPT) \
	$(WG_CHECK_SCRIPT) \
	$(WG_SERVER_BASE_RENDER_SCRIPT) \
	$(WG_RENDER_CHECK_SCRIPT) \
	$(WG_RECORD_COMPROMISED_KEYS_SCRIPT) \
	$(WG_REMOVE_CLIENT) \
	$(WG_ROTATE_CLIENT)

wg-clean-out: ensure-run-as-root 
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🧹 cleaning WireGuard scratch output"; fi
	@$(run_as_root) rm -rf "$(WG_ROOT)/out/clients"

# ------------------------------------------------------------
# Compile intent → plan.tsv
# ------------------------------------------------------------
wg-compile-intent: wg-install-scripts wg-clean-out
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_COMPILE_SCRIPT)"

wg-ensure-server-keys: wg-install-scripts wg-compile-intent
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_SERVER_KEYS_SCRIPT)"

# ------------------------------------------------------------
# Generate client keys → keys.tsv
# ------------------------------------------------------------
wg-compile-keys: wg-install-scripts wg-compile-intent
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_KEYS_SCRIPT)"

# ------------------------------------------------------------
# Render client + server configs from plan.tsv + keys.tsv
# ------------------------------------------------------------
wg-render-server-base: wg-install-scripts wg-ensure-server-keys
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_SERVER_BASE_RENDER_SCRIPT)"

wg-render: wg-install-scripts wg-compile-intent wg-compile-keys wg-render-server-base
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_RENDER_SCRIPT)"

wg-render-missing: wg-install-scripts wg-compile-intent wg-compile-keys wg-render-server-base
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_RENDER_MISSING_SCRIPT)"

$(WG_ROOT)/compiled/plan.tsv: wg-compile-intent

# ------------------------------------------------------------
# Compile everything (no deployment)
# ------------------------------------------------------------
wg-compile: wg-install-scripts wg-compile-intent wg-compile-keys wg-render wg-check-render wg-check

# ------------------------------------------------------------
# Deploy compiled state (requires successful compile)
# ------------------------------------------------------------
wg-deployed: wg-install-scripts ensure-run-as-root net-tunnel-preflight wg-compile wg-check
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🔄 WireGuard deployment requested"; fi
	@$(run_as_root) $(WG_DEPLOY_SCRIPT)

wg-apply-verified: wg-apply wg-verify-no-key-reuse wg-verify-no-legacy-keys

wg-apply: wg-install-scripts wg-deployed
	@$(run_as_root) $(WG_EXPORT_SCRIPT)

	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🔁 Reconciling WireGuard kernel state"; fi

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
			# First bring-up: wg-quick installs routes/rules derived from AllowedIPs. \
			wg-quick up "$$iface" >/dev/null; \
		else \
			# Update peers/keys without tearing down interface state (routes stay). \
			wg syncconf "$$iface" <(wg-quick strip "$$conf"); \
		fi; \
		ip link set mtu 1420 dev "$$iface" 2>/dev/null || true; \
		ip link set up dev "$$iface" 2>/dev/null || true; \
		# Hard guard: routes must exist (otherwise we’re back to “no connectivity”). \
		if ! ip route show dev "$$iface" | grep -q . && ! ip -6 route show dev "$$iface" | grep -q .; then \
			echo "wg-apply: ERROR: $$iface has no routes (v4 or v6)" >&2; \
			exit 1; \
		fi; \
	done; \
	'

	@if [ "$(VERBOSE)" -ge 1 ]; then echo "✅ WireGuard kernel state converged"; fi

# ------------------------------------------------------------
# Consistency / sanity checks
# ------------------------------------------------------------
wg-check: wg-install-scripts ensure-run-as-root
	@$(run_as_root) $(WG_CHECK_SCRIPT)

wg-rebuild-clean: wg-install-scripts ensure-run-as-root 
	@echo "🔥 FULL WireGuard rebuild (keys + config)"
	@echo "⚠️  This will invalidate ALL existing clients"
	@echo "⚠️  Press Ctrl-C now if this is not intended"
	@sleep 5
	@echo "▶ recording compromised WireGuard keys and destroying existing WireGuard state"
	@$(run_as_root) $(WG_RECORD_COMPROMISED_KEYS_SCRIPT)

wg-rebuild-guard:
	@if [ "$(FORCE)" != "1" ]; then \
		echo "❌ wg-rebuild-all is destructive. Re-run with FORCE=1"; \
		exit 1; \
	fi

wg-rebuild-all: \
	wg-rebuild-guard \
	wg-install-scripts \
	wg-rebuild-clean \
	wg-ensure-server-keys \
	wg-apply-verified
	@echo "🔥 WireGuard fully rebuilt with fresh keys"

wg-check-render: wg-install-scripts wg-render
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) "$(WG_RENDER_CHECK_SCRIPT)"

wg: \
	wg-ensure-server-keys \
	wg-render-missing \
	wg-apply-verified \
	wg-intent \
	wg-dashboard \
	wg-status \
	wg-runtime \
	wg-clients

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
			echo "---- active fingerprints ----"; \
			cat "$$tmp"; \
			echo "----------------------------"; \
			exit 1; \
		fi; \
		echo "✅ No compromised keys in active WireGuard state"; \
	'

wg-verify-no-legacy-keys: wg-install-scripts ensure-run-as-root
	@test ! -d /etc/wireguard/.legacy || { \
		echo "❌ ERROR: legacy WireGuard key directory exists (/etc/wireguard/.legacy)"; \
		exit 1; \
	}

wg-rotate-client: wg-install-scripts ensure-run-as-root
	@if [ -z "$(base)" ] || [ -z "$(iface)" ]; then \
		echo "Usage: make wg-rotate-client base=<base> iface=<iface>"; \
		exit 1; \
	fi
	@echo "🔁 Rotating WireGuard client: base=$(base) iface=$(iface)"
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) $(INSTALL_PATH)/wg-rotate-client.sh "$(base)" "$(iface)"
	@echo "➡️  Now run: make wg"

wg-remove-client: wg-install-scripts ensure-run-as-root
	@if [ -z "$(base)" ] || [ -z "$(iface)" ]; then \
		echo "Usage: make wg-remove-client base=<base> iface=<iface>"; \
		exit 1; \
	fi
	@echo "🗑️  Removing WireGuard client: base=$(base) iface=$(iface)"
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) $(INSTALL_PATH)/wg-remove-client.sh "$(base)" "$(iface)"
	@echo "➡️  Now run: make wg"
