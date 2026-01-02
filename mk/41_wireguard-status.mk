# ============================================================
# mk/41_wireguard-status.mk — WireGuard status orchestration (no heredoc)
# - Production-ready, minimal duplication, robust shell usage
# - Avoids make-level word() expansion; computes per-iface values at runtime
# - Does not use heredoc to write files (uses printf | tee)
# - All privileged actions go through $(run_as_root)
# ============================================================


# --- Dashboard: list users, machines, and interfaces (space-delimited) ---
.PHONY: client-dashboard client-dashboard-status
client-dashboard-status:
	@true

client-dashboard: client-dashboard-status
	@printf "%-8s %-10s %-3s %-3s %-3s %-3s %-3s %-3s %-3s %-3s\n" "USER" "MACHINE" "wg0" "wg1" "wg2" "wg3" "wg4" "wg5" "wg6" "wg7"
	@printf "%-8s %-10s %-3s %-3s %-3s %-3s %-3s %-3s %-3s %-3s\n" "--------" "----------" "---" "---" "---" "---" "---" "---" "---" "---"
	@$(run_as_root) sh -c '\
		TMP=$$(mktemp); \
		for f in $(WG_DIR)/*-wg*.conf; do \
			[ -f "$$f" ] || continue; \
			name=$$(basename "$$f" .conf); \
			base=$$(echo "$$name" | sed -n '\''s/-wg[0-7]$$//p'\''); \
			[ -n "$$base" ] && echo "$$base" >> "$$TMP"; \
		done; \
		if [ ! -s "$$TMP" ]; then \
			echo "No client configs found."; rm -f "$$TMP"; exit 0; \
		fi; \
		sort -u "$$TMP" -o "$$TMP"; \
		while read -r base; do \
			user=$$(echo "$$base" | awk -F- '\''{print $$1}'\''); \
			machine=$$(echo "$$base" | awk -F- '\''{print $$2}'\''); \
			row=( "$$user" "$$machine" ); \
			for i in 0 1 2 3 4 5 6 7; do \
				if [ -f "$(WG_DIR)/$$base-wg$$i.conf" ]; then val="✅ "; else val="-"; fi; \
				row+=( "$$val" ); \
			done; \
			printf "%-8s %-10s %-3s %-3s %-3s %-3s %-3s %-3s %-3s %-3s\n" "$${row[0]}" "$${row[1]}" "$${row[2]}" "$${row[3]}" "$${row[4]}" "$${row[5]}" "$${row[6]}" "$${row[7]}" "$${row[8]}" "$${row[9]}"; \
		done < "$$TMP"; \
		rm -f "$$TMP"' 

# --- wg-status: space-delimited interface table (no private key) ---
.PHONY: wg-status
wg-status:
	@echo "WireGuard status summary:"
	@printf "%-6s %-12s %-44s %-6s %-8s %-s\n" "IFACE" "LINK" "PUBLIC_KEY(short)" "PORT" "PEERS" "SAMPLE_ALLOWEDIPS"
	@printf "%-6s %-12s %-44s %-6s %-8s %-s\n" "------" "------------" "--------------------------------------------" "------" "------" "--------------------"
	@$(run_as_root) sh -c '\
		for i in $(WG_IFACES); do \
			dev=wg$$i; conf="$(WG_DIR)/$$dev.conf"; \
			# link state (brief) \
			link_line=$$(ip -brief link show "$$dev" 2>/dev/null || echo "not-present"); \
			# pick a concise link token (UP/DOWN/UNKNOWN/not-present) \
			link_state=$$(printf "%s" "$$link_line" | awk '\''{print ($$2 ? $$2 : $$1)}'\''); \
			# gather wg output if present \
			wg_out=$$($(WG_BIN) show "$$dev" 2>/dev/null || true); \
			if [ -n "$$wg_out" ]; then \
				pub=$$(printf "%s" "$$wg_out" | sed -n '\''s/^[[:space:]]*public key:[[:space:]]*//p'\'' | head -n1); \
				port=$$(printf "%s" "$$wg_out" | sed -n '\''s/^[[:space:]]*listening port:[[:space:]]*//p'\'' | head -n1); \
				peer_count=$$(printf "%s" "$$wg_out" | grep -c '^peer:' || true); \
				sample_allowed=$$(printf "%s" "$$wg_out" | sed -n '\''s/^[[:space:]]*AllowedIPs[[:space:]]*=[[:space:]]*//Ip'\'' | head -n1 | tr -d \"\\n\" ); \
			else \
				pub="(none)"; port="-"; peer_count=0; sample_allowed="-"; \
			fi; \
			# shorten public key for display (first 8 + ... + last 8) \
			if [ "$$pub" != "(none)" ] && [ -n "$$pub" ]; then \
				pub_short=$$(printf "%s" "$$pub" | awk '\''{s=$$0; printf substr(s,1,8) "..." substr(s,length(s)-7)}'\''); \
			else \
				pub_short="(none)"; \
			fi; \
			# note if config file missing \
			if [ ! -f "$$conf" ]; then cfg_note="(no-conf)"; else cfg_note=""; fi; \
			# print aligned space-delimited row \
			printf "%-6s %-12s %-44s %-6s %-8s %-s\n" "$$dev" "$$link_state$$cfg_note" "$$pub_short" "$$port" "$$peer_count" "$$sample_allowed"; \
		done; \
		echo ""'

.PHONY: wg-status2
wg-status2:
	@echo "WireGuard peer status (resolved names from /etc/wireguard/client-map.csv)"
	@$(SHELL) scripts/wg-status2.sh

.PHONY: client-remove
client-remove:
	@# Usage: make client-remove BASE=<base> IFACE=<iface>
	@if [ -z "$(BASE)" ] || [ -z "$(IFACE)" ]; then \
		echo "Usage: make client-remove BASE=<base> IFACE=<iface>"; exit 1; \
	fi
	@echo "🗑 removing client $(BASE) on $(IFACE)"
	$(run_as_root) "$(CURDIR)/scripts/remove-client.sh" "$(BASE)" "$(IFACE)"