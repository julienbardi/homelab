# ============================================================
# mk/41_wireguard-status.mk — WireGuard status & inspection
#
# Architecture-aligned status views:
# - Intent view:     $(WG_ROOT)/compiled/plan.tsv (authoritative)
# - Compiled view:   $(WG_ROOT)/compiled/* (keys, pubkeys, exports)
# - Deployed view:   /etc/wireguard (installed configs/keys)
# - Runtime view:    wg show (kernel state)
#
# Notes:
# - No hard-coded iface ranges.
# - plan.tsv is treated as strict TSV; comments/blank/header are skipped.
# - All privileged actions go through $(run_as_root).
# ============================================================

WG_DIR ?= /etc/wireguard
WG_BIN ?= /usr/bin/wg

PLAN := $(WG_ROOT)/compiled/plan.tsv

SERVER_PUBDIR := $(WG_ROOT)/compiled/server-pubkeys
CLIENT_KEYDIR := $(WG_ROOT)/compiled/client-keys
EXPORT_DIR    := $(WG_ROOT)/export/clients

WG_PLAN_IFACES   := $(INSTALL_PATH)/wg-plan-ifaces.sh
WG_RUNTIME       := $(INSTALL_PATH)/wg-runtime.sh
WG_PLAN_READ     := $(INSTALL_PATH)/wg-plan-read.sh

.PHONY: \
	wg-clients \
	wg-show-client-key-validate \
	wg-show-client-key \
	wg-intent \
	wg-compiled wg-deployed-view \
	wg-status wg-runtime \
	wg-dashboard \
	wg-check-ports

# ------------------------------------------------------------
# Helpers (kept in Make for portability, but still dumb)
# ------------------------------------------------------------

define WG_PLAN_ROWS
awk -F'\t' '\
	/^#/ { next } \
	/^[[:space:]]*$$/ { next } \
	$$1=="base" && $$2=="iface" && $$3=="slot" { next } \
	{ print } \
' "$(PLAN)"
endef

# ------------------------------------------------------------
# Intent view (authoritative)
# ------------------------------------------------------------

wg-intent:
	@echo "📋 WireGuard client addressing (make wg-intent)"
	@printf "%-14s %-6s %-7s %-18s %s\n" \
		"BASE" "IFACE" "HOSTID" "ADDRESS" "ENDPOINT"
	@printf "%-14s %-6s %-7s %-18s %s\n" \
		"--------------" "------" "-------" "------------------" "------------------------------"
	@$(WG_PLAN_ROWS) | awk -F'\t' '{ \
		printf "%-14s %-6s %-7s %-18s %s\n", $$1, $$2, $$3, $$5, $$9 \
	}'

wg-clients: wg-compile
	@echo "📋 WireGuard client summary (make wg-clients)"
	@$(WG_PLAN_ROWS) | awk -F'\t' '\
		{ \
			base=$$1; iface=$$2; \
			n=split(base,a,"-"); user=a[1]; machine=(n>=2?a[2]:""); \
			printf "%-8s %-12s %-6s make wg-show-client-key BASE=%s IFACE=%s\n", \
				user, machine, iface, base, iface \
		}'

.PHONY: wg-show-client-key-validate
wg-show-client-key-validate:
	@if [ -z "$(BASE)" ] || [ -z "$(IFACE)" ]; then \
		echo "Usage: make wg-show-client-key BASE=<base> IFACE=<iface>" >&2; \
		exit 1; \
	fi

wg-show-client-key: wg-show-client-key-validate ensure-run-as-root
	@conf="$(WG_ROOT)/export/clients/$(BASE)/$(IFACE).conf"; \
	$(run_as_root) test -f "$$conf" || { \
		echo "ERROR: missing $$conf — run 'make wg' first" >&2; \
		exit 1; \
	}; \
	$(run_as_root) cat "$$conf"

# ------------------------------------------------------------
# Compiled artifacts view
# ------------------------------------------------------------

wg-compiled: $(WG_PLAN_IFACES) $(WG_PLAN_READ)
	@echo "Compiled artifacts:"
	@echo "  plan:        $(PLAN)"
	@echo "  server pubs: $(SERVER_PUBDIR)"
	@echo "  client keys: $(CLIENT_KEYDIR)"
	@echo "  exports:     $(EXPORT_DIR)"
	@echo
	@echo "Interfaces (from intent):"
	@$(WG_PLAN_IFACES) "$(PLAN)" | sed 's/^/  - /'
	@echo
	@echo "Server pubkeys present:"
	@ls -1 "$(SERVER_PUBDIR)"/*.pub 2>/dev/null | sed 's|.*/|  - |' || echo "  (none)"
	@echo
	@echo "Client keys present:"
	@ls -1 "$(CLIENT_KEYDIR)"/*.key 2>/dev/null | sed 's|.*/|  - |' || echo "  (none)"
	@echo
	@echo "Exported client configs present:"
	@ls -1 "$(EXPORT_DIR)"/*/*.conf 2>/dev/null | sed 's|.*/|  - |' || echo "  (none)"

# ------------------------------------------------------------
# Deployed view
# ------------------------------------------------------------

wg-deployed-view: ensure-run-as-root
	@echo "Deployed /etc/wireguard view:"
	@$(run_as_root) env WG_ROOT="$(WG_ROOT)" sh -c '\
		set -e; \
		if [ ! -d "$(WG_DIR)" ]; then \
			echo "missing $(WG_DIR)"; exit 1; \
		fi; \
		echo; \
		echo "Configs:"; \
		ls -1 "$(WG_DIR)"/*.conf 2>/dev/null || echo "  (none)"; \
		echo; \
		echo "Public keys:"; \
		ls -1 "$(WG_DIR)"/*.pub 2>/dev/null || echo "  (none)"; \
		echo; \
		echo "Metadata:"; \
		ls -1 "$(WG_DIR)"/.deploy-meta "$(WG_DIR)"/last-known-good.list 2>/dev/null || echo "  (none)"; \
		echo; \
		echo "Unexpected files:"; \
		ls -1 "$(WG_DIR)" | grep -Ev "^(wg.*\\.(conf|pub)|\\.deploy-meta|last-known-good\\.list)$$" || echo "  (none)"; \
	'

# ------------------------------------------------------------
# Runtime view
# ------------------------------------------------------------

wg-runtime: ensure-run-as-root $(WG_RUNTIME)
	@echo
	@echo "📋 WireGuard peer state (make wg-runtime)"
	@$(run_as_root) env WG_ROOT="$(WG_ROOT)" "$(WG_RUNTIME)"

wg-status: ensure-run-as-root $(WG_PLAN_IFACES)
	@echo
	@echo "📋 WireGuard runtime interface status (make wg-status)"
	@printf "%-6s %-12s %-18s %-8s %-s\n" "IFACE" "LINK" "PORT" "PEERS"
	@printf "%-6s %-12s %-18s %-8s %-s\n" "------" "------------" "------------------" "--------"
	@$(run_as_root) env WG_ROOT="$(WG_ROOT)" sh -c '\
		set -e; \
		IFACES="$$( "$(WG_PLAN_IFACES)" "$(PLAN)" )"; \
		for dev in $$IFACES; do \
			link_line=$$(ip -brief link show "$$dev" 2>/dev/null || echo "not-present"); \
			link_state=$$(printf "%s" "$$link_line" | awk '\''{print ($$2 ? $$2 : $$1)}'\''); \
			wg_out=$$($(WG_BIN) show "$$dev" 2>/dev/null || true); \
			if [ -n "$$wg_out" ]; then \
				port=$$(printf "%s" "$$wg_out" | sed -n '\''s/^[[:space:]]*listening port:[[:space:]]*//p'\'' | head -n1); \
				peer_count=$$(printf "%s" "$$wg_out" | grep -c "^peer:" || true); \
			else \
				port="-"; peer_count=0; \
			fi; \
			printf "%-6s %-12s %-18s %-8s\n" "$$dev" "$$link_state" "$$port" "$$peer_count"; \
		done \
	'

# ------------------------------------------------------------
# Dashboard
# ------------------------------------------------------------

wg-dashboard:
	@echo
	@echo "📋 WireGuard interface assignment (make wg-dashboard)"
	@printf "%-24s %s\n" "BASE" "IFACES"
	@printf "%-24s %s\n" "------------------------" "------------------------------"
	@$(WG_PLAN_ROWS) | awk -F'\t' '\
		{ seen[$$1]=seen[$$1] " " $$2 } \
		END { for (b in seen) printf "%-24s%s\n", b, seen[b] } \
	' | sort

wg-check-ports: $(WG_PLAN_IFACES)
	@echo "Checking WireGuard UDP ports..."
	@$(WG_PLAN_IFACES) "$(PLAN)" | sort -u | while read iface; do \
		port="$$(sudo wg show $$iface listen-port 2>/dev/null || true)"; \
		if [ -z "$$port" ]; then \
			printf "⚠️ %-5s UDP (unknown) : INTERFACE NOT FOUND \n" "$$iface"; \
		elif [ "$$port" = "0" ]; then \
			printf "🔕 %-5s UDP 0         : NOT LISTENING (outbound-only)\n" "$$iface"; \
		else \
			printf "✅  %-5s UDP %-5s : LISTENING \n" "$$iface" "$$port"; \
			if [ "$$port" -lt 51420 ] || [ "$$port" -gt 51451 ]; then \
				printf "        ⚠️  Port %s is outside forwarded range (UDP 51420–51451)\n" "$$port"; \
			fi; \
		fi; \
	done
