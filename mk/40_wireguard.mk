# ============================================================
# mk/40_wireguard.mk — WireGuard orchestration (no heredoc)
# - Production-ready, minimal duplication, robust shell usage
# - Avoids make-level word() expansion; computes per-iface values at runtime
# - Does not use heredoc to write files (uses printf | tee)
# - All privileged actions go through $(run_as_root)
# ============================================================

# run_as_root inherited from mk/01_common.mk
WG_DIR := /etc/wireguard
MAP_FILE := /etc/wireguard/client-map.csv
WG_BIN := /usr/bin/wg
WG_QUICK := /usr/bin/wg-quick

MAKEFLAGS += --no-print-directory
export FORCE CONF_FORCE FORCE_REASSIGN SERVER_HOST

SERVER_HOST := vpn.bardi.ch
# Per-interface data (index order must match)
WG_IFACES := 0 1 2 3 4 5 6 7
WG_PORTS  := 51420 51421 51422 51423 51424 51425 51426 51427
WG_IPV4S  := 10.10.0.1/24 10.11.0.1/24 10.12.0.1/24 10.13.0.1/24 10.14.0.1/24 10.15.0.1/24 10.16.0.1/24 10.17.0.1/24
WG_IPV6S  := 2a01:8b81:4800:9c00:10::1/128 2a01:8b81:4800:9c00:11::1/128 2a01:8b81:4800:9c00:12::1/128 2a01:8b81:4800:9c00:13::1/128 \
			 2a01:8b81:4800:9c00:14::1/128 2a01:8b81:4800:9c00:15::1/128 2a01:8b81:4800:9c00:16::1/128 2a01:8b81:4800:9c00:17::1/128

# Embedded clients inventory (format: base:wgN)
CLIENTS := \
	julie-s22:wg0 \
	julie-s22:wg1 \
	julie-s22:wg2 \
	julie-s22:wg3 \
	julie-s22:wg4 \
	julie-s22:wg5 \
	julie-s22:wg6 \
	julie-s22:wg7 \
	julie-omen30l:wg0 \
	julie-omen30l:wg1 \
	julie-omen30l:wg2 \
	julie-omen30l:wg3 \
	julie-omen30l:wg4 \
	julie-omen30l:wg5 \
	julie-omen30l:wg6 \
	julie-omen30l:wg7 \
	julie-acer:wg0 \
	julie-acer:wg1 \
	julie-acer:wg2 \
	julie-acer:wg3 \
	julie-acer:wg4 \
	julie-acer:wg5 \
	julie-acer:wg6 \
	julie-acer:wg7

.PHONY: ensure-wg-dir all-wg all-wg-up all-clients-generate wg-add-peers regen-clients client-list wg-reinstall-all

# Ensure WG_DIR and map file exist with safe perms
ensure-wg-dir:
	@$(run_as_root) install -d -m 0700 $(WG_DIR)
	@$(run_as_root) sh -c 'test -f "$(MAP_FILE)" || install -m 0600 /dev/null "$(MAP_FILE)"'
	@$(run_as_root) chown root:root $(MAP_FILE) || true

# Generic server config generator for wgN (no make-level word() usage)
# Usage: make wg3  or make wg% (pattern)
wg%: ensure-wg-dir
	@N=$*; \
	INDEX=$$((N+1)); \
	# compute values at runtime using shell (cut selects the INDEX-th field)
	PORT=$$(echo "$(WG_PORTS)" | cut -d' ' -f$$INDEX); \
	IPV4=$$(echo "$(WG_IPV4S)" | cut -d' ' -f$$INDEX); \
	IPV6=$$(echo "$(WG_IPV6S)" | cut -d' ' -f$$INDEX); \
	DEV=wg$$N; \
	KEY="$(WG_DIR)/$$DEV.key"; PUB="$(WG_DIR)/$$DEV.pub"; CONF="$(WG_DIR)/$$DEV.conf"; \
	echo "🔧 ensure $$DEV (PORT=$$PORT, IPV4=$$IPV4, IPV6=$$IPV6)"; \
	# generate keypair if missing or FORCE=1
	if [ -f "$$KEY" ] && [ "$(FORCE)" != "1" ]; then \
		echo "🔒 $$KEY exists, skipping key generation"; \
	else \
		$(run_as_root) sh -c 'KEY="'"$$KEY"'" PUB="'"$$PUB"'" ; $(WG_BIN) genkey | tee "$$KEY" | $(WG_BIN) pubkey > "$$PUB"'; \
		$(run_as_root) chmod 600 "$$KEY" "$$PUB"; \
		echo "✅ generated $$KEY and $$PUB"; \
	fi; \
	PRIVKEY=$$($(run_as_root) cat "$$KEY"); \
	# write conf if missing or CONF_FORCE=1 (use printf to avoid heredoc)
	if [ "$(CONF_FORCE)" = "1" ] || [ ! -f "$$CONF" ]; then \
		printf "%s\n%s\n%s\n%s\n" "[Interface]" "Address = $$IPV4, $$IPV6" "ListenPort = $$PORT" "PrivateKey = $$PRIVKEY" | $(run_as_root) tee "$$CONF" > /dev/null; \
		$(run_as_root) chmod 600 "$$CONF"; \
		echo "📄 wrote $$CONF"; \
		$(run_as_root) sh -c 'DEV="'"$$DEV"'" ; FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) $(MAKE) regen-clients IFACE=$$DEV' || echo "⚠️ regen-clients failed for $$DEV"; \
	else \
		echo "⏭ $$CONF exists and CONF_FORCE!=1, skipping"; \
	fi

# Named client configs (create only; do NOT print QR)
client-%: ensure-wg-dir
	@STEM="$*"; \
	# infer IFACE from the original stem first (so we don't lose -wgN)
	IFACE="$(IFACE)"; \
	if [ -z "$$IFACE" ]; then IFACE=$$(echo "$$STEM" | sed -n "s/.*-\(wg[0-7]\)$$/\1/p"); fi; \
	[ -n "$$IFACE" ] || { echo "❌ must specify IFACE=wgN when client name does not include -wgN"; exit 1; }; \
	# sanitize BASE: strip leading generate- and trailing -wgN for the name passed to the generator
	BASE="$$(printf '%s' "$$STEM" | sed -e 's/^generate-//' -e 's/-wg[0-9]$$//')"; \
	echo "🧩 generating client $$BASE for $$IFACE"; \
	IFACE_INDEX=$$(printf '%s' "$$IFACE" | sed -n 's/^wg\([0-9]\+\)$$/\1/p'); \
	if [ -n "$$IFACE_INDEX" ]; then \
		IDX=$$((IFACE_INDEX + 1)); \
		SERVER_PORT_VAL=$$(echo "$(WG_PORTS)" | cut -d' ' -f$$IDX); \
	else \
		SERVER_PORT_VAL=""; \
	fi; \
	$(run_as_root) sh -c 'SERVER_HOST=$(SERVER_HOST) SERVER_PORT='"$$SERVER_PORT_VAL"' FORCE_REASSIGN=$(FORCE_REASSIGN) FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) exec "$(CURDIR)/scripts/gen-client.sh" "'"$$BASE"'" "'"$$IFACE"'"'

# Show QR for client; auto-create if missing
client-showqr-%:
	@STEM="$*"; \
	# infer IFACE if present in name
	case "$$STEM" in \
		*-wg[0-7]) BASE=$$(echo "$$STEM" | sed -n 's/^\(.*\)-wg\([0-7]\)$$/\1/p'); IFACE=$$(echo "$$STEM" | sed -n 's/^.*-\(wg[0-7]\)$$/\1/p'); ;; \
		*) BASE="$$STEM"; IFACE="$(IFACE)"; ;; \
	esac; \
	if [ -z "$$IFACE" ]; then echo "❌ cannot infer IFACE; run: make client-<name> IFACE=wgN"; exit 1; fi; \
	CONFNAME="$$BASE-$$IFACE"; \
	echo "ℹ️ ensuring client $$CONFNAME exists then printing QR"; \
	$(run_as_root) sh -c 'FORCE_REASSIGN=$(FORCE_REASSIGN) FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) $(MAKE) client-'"$$BASE"' IFACE='"$$IFACE"'' || { echo "❌ failed to create $$CONFNAME"; exit 1; }; \
	$(run_as_root) sh -c 'qrencode -t ANSIUTF8 < "$(WG_DIR)/'"$$CONFNAME"'.conf"'


# Bring up/down interfaces (idempotent)
wg-up-%:
	@DEV=wg$*; CONF="$(WG_DIR)/$$DEV.conf"; \
	if [ ! -f "$$CONF" ]; then echo "⏭ $$DEV: no config at $$CONF"; exit 0; fi; \
	echo "⏫ starting $$DEV"; \
	# clean restart if present
	if ip link show "$$DEV" >/dev/null 2>&1; then $(run_as_root) $(WG_QUICK) down "$$DEV" >/dev/null 2>&1 || true; fi; \
	$(run_as_root) $(WG_QUICK) up "$$DEV" || { echo "❌ failed to bring up $$DEV"; journalctl -u wg-quick@$$DEV -n 60 --no-pager || true; exit 1; }; \
	echo "✅ $$DEV up"; $(run_as_root) $(WG_BIN) show "$$DEV" || true

wg-down-%:
	@DEV=wg$*; \
	echo "⏬ stopping $$DEV"; \
	if ip link show "$$DEV" >/dev/null 2>&1 || $(WG_QUICK) status "$$DEV" >/dev/null 2>&1; then \
		$(run_as_root) $(WG_QUICK) down "$$DEV" || { echo "❌ failed to bring down $$DEV"; exit 1; }; \
	else \
		echo "⏭ $$DEV not present"; \
	fi

# Preview and destructive clean for clients bound to an interface
wg-clean-list-%:
	@echo "🗑️ clients for wg$* (preview):"; ls -1 $(WG_DIR)/*-wg$*.conf 2>/dev/null || echo "⏭ none"

wg-clean-%:
	@echo "🧹 revoking clients for wg$*"; \
	TO_REMOVE=$$(ls -1 $(WG_DIR)/*-wg$*.conf $(WG_DIR)/*-wg$*.key $(WG_DIR)/*-wg$*.pub 2>/dev/null || true); \
	if [ -z "$$TO_REMOVE" ]; then echo "⏭ none"; else echo "$$TO_REMOVE"; $(run_as_root) sh -c 'rm -f $(WG_DIR)/*-wg$*.conf $(WG_DIR)/*-wg$*.key $(WG_DIR)/*-wg$*.pub'; echo "✅ removed"; fi

# Client inventory (simple, robust)
client-list:
	@echo "Clients in $(WG_DIR):"; \
	for f in $(WG_DIR)/*-wg*.conf; do [ -f "$$f" ] || continue; base=$$(basename "$$f" .conf); printf "%s\n" "$$base"; done

# Bulk helpers
ALL_WG := $(addprefix wg,$(WG_IFACES))

all-wg: $(ALL_WG)
	@echo "✅ all server configs ensured"

all-wg-up: ensure-wg-dir
	@echo "⏫ bringing up all wg interfaces"
	for i in $(WG_IFACES); do $(run_as_root) /usr/bin/make -s wg-up-$$i || { echo "❌ wg-up-$$i failed"; exit 1; }; \
	done
	@echo "✅ all-wg-up finished"

# Generate missing clients from CLIENTS list
all-clients-generate:
	@echo "🛠 generating missing clients from CLIENTS"; \
	for entry in $(CLIENTS); do base=$$(echo $$entry | sed 's/:.*//'); iface=$$(echo $$entry | sed 's/.*://'); CONFNAME="$$base-$$iface"; \
		if [ ! -f "$(WG_DIR)/$$CONFNAME.conf" ] || [ ! -f "$(WG_DIR)/$$CONFNAME.key" ]; then \
			echo "➕ creating $$CONFNAME"; $(run_as_root) sh -c 'FORCE_REASSIGN=$(FORCE_REASSIGN) FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) $(MAKE) client-'"$$base"' IFACE='"$$iface"'' || { echo "❌ failed $$CONFNAME"; exit 1; }; \
		else echo "✅ $$CONFNAME exists"; fi; \
	done; echo "✅ client generation complete"

# Ensure peers are present in server configs and reload
wg-add-peers:
	@echo "🔗 ensuring peers from CLIENTS"; \
	$(run_as_root) sh -c '\
		for entry in $(CLIENTS); do \
			base=$$(echo $$entry | sed "s/:.*//"); iface=$$(echo $$entry | sed "s/.*://"); \
			conf="$(WG_DIR)/$$iface.conf"; client_pub="$(WG_DIR)/$$base-$$iface.pub"; client_key="$(WG_DIR)/$$base-$$iface.key"; client_conf="$(WG_DIR)/$$base-$$iface.conf"; \
			[ -f "$$client_pub" ] || { [ -f "$$client_key" ] && $(WG_BIN) pubkey < "$$client_key" > "$$client_pub" || echo "⚠️ missing pub for $$base-$$iface"; }; \
			[ -f "$$client_pub" ] || continue; [ -f "$$conf" ] || continue; \
			PUB=$$(cat "$$client_pub"); grep -qF "$$PUB" "$$conf" && { echo "✅ $$base-$$iface already in $$conf"; continue; }; \
			ALLOWED=$$(grep -m1 -E "^[[:space:]]*Address" "$$client_conf" 2>/dev/null | sed -E "s/^[[:space:]]*Address[[:space:]]*=[[:space:]]*//" || true); \
			[ -z "$$ALLOWED" ] && ALLOWED="0.0.0.0/32"; \
			echo "➕ adding peer $$base-$$iface to $$conf"; \
			$(WG_BIN) set $$iface peer "$$PUB" allowed-ips "$$ALLOWED" || echo "⚠️ wg set failed for $$base-$$iface"; \
			printf "\n[Peer]\n# %s\nPublicKey = %s\nAllowedIPs = %s\n" "$$base-$$iface" "$$PUB" "$$ALLOWED" | tee -a "$$conf" > /dev/null; \
			$(WG_QUICK) down $$iface >/dev/null 2>&1 || true; $(WG_QUICK) up $$iface >/dev/null 2>&1 || true; \
		done; echo "✅ wg-add-peers complete"'

# Regenerate clients for a given IFACE (IFACE=wgN)
regen-clients:
	@if [ -z "$(IFACE)" ]; then echo "❌ regen-clients requires IFACE=wgN"; exit 1; fi; \
	echo "♻️ regenerating clients for $(IFACE)"; \
	for entry in $(CLIENTS); do base=$$(echo $$entry | sed 's/:.*//'); iface=$$(echo $$entry | sed 's/.*://'); \
		if [ "$$iface" = "$(IFACE)" ]; then echo "🔁 regenerating $$base"; $(run_as_root) sh -c 'FORCE_REASSIGN=$(FORCE_REASSIGN) FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) $(MAKE) client-'"$$base"' IFACE='"$(IFACE)"'' || echo "⚠️ failed $$base"; fi; \
	done; echo "✅ regen-clients complete for $(IFACE)"

# Destructive full reinstall (interactive confirmation)
.PHONY: wg-reinstall-all
wg-reinstall-all:
	@echo "[make] WARNING: destructive reinstall of WireGuard server + client artifacts (map file recreated)"
	@echo ""
	@echo "This will:"
	@echo "  - stop any running wg interfaces (wg0..wg7)"
	@echo "  - remove server configs and keys: $(WG_DIR)/wg*.conf $(WG_DIR)/wg*.key $(WG_DIR)/wg*.pub"
	@echo "  - remove client artifacts: $(WG_DIR)/*-wg*.conf $(WG_DIR)/*-wg*.key $(WG_DIR)/*-wg*.pub"
	@echo "  - recreate empty map file: $(MAP_FILE)"
	@echo ""
	@echo "Before proceeding you should verify and securely share any public keys you need to keep."
	@echo "  - To list public keys (copy/paste or save):"
	@echo "      sudo ls -la $(WG_DIR)/*.pub"
	@echo "  - To display a client's QR code locally (scan with mobile):"
	@echo "      sudo make client-showqr-<base>-<iface>    # e.g. sudo make client-showqr-julie-s22-wg3"
	@echo ""
	@echo "Secure sharing suggestions:"
	@echo "  - Use an end-to-end channel (Signal, Wire, or similar) to send public key text."
	@echo "  - Or scan the QR code locally rather than sending files over chat/email."
	@echo ""
	@bash -c 'read -r -p "Type YES to confirm destructive reinstall: " CONFIRM; \
		if [ "$$CONFIRM" != "YES" ]; then echo "[make] Aborted by user (confirmation not YES)"; exit 1; fi; \
		echo "[make] Proceeding with destructive reinstall..." ; \
		# stop interfaces (idempotent) \
		for i in 0 1 2 3 4 5 6 7; do $(MAKE) wg-down-$$i || true; done; \
		# remove artifacts \
		$(run_as_root) rm -f $(WG_DIR)/wg*.conf $(WG_DIR)/wg*.key $(WG_DIR)/wg*.pub $(WG_DIR)/*-wg*.conf $(WG_DIR)/*-wg*.key $(WG_DIR)/*-wg*.pub || true; \
		# ensure dir and recreate map file \
		$(run_as_root) install -d -m 0700 $(WG_DIR); \
		$(run_as_root) install -m 0600 /dev/null $(MAP_FILE); \
		$(run_as_root) chown root:root $(MAP_FILE) || true; \
		# regenerate servers and clients (force keys+confs) \
		sudo sh -c "FORCE_REASSIGN=1 FORCE=1 CONF_FORCE=1 /usr/bin/make -B all-wg"; \
		sudo sh -c "FORCE_REASSIGN=1 FORCE=1 CONF_FORCE=1 /usr/bin/make -B all-clients-generate"; \
		# program peers and bring up interfaces \
		$(run_as_root) /usr/bin/make wg-add-peers; \
		$(run_as_root) /usr/bin/make all-wg-up; \
		echo \"[make] wg-reinstall-all complete\"'