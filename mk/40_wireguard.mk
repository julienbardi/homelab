# ============================================================
# mk/40_wireguard.mk — WireGuard orchestration
# ============================================================
# CONTRACT:
# - Uses run_as_root := ./bin/run-as-root
# - All recipes call $(run_as_root) with argv tokens.
# - Generates wg0–wg7 configs under /etc/wireguard
# - Generates named client configs: <user>-<machine>-wgX.conf
# - Auto-creates server key if missing and brings interface up when creating a client
# - DNS fixed to 10.89.12.4
# - Prints QR code for mobile onboarding (requires qrencode)
# - Provides wg-up-% and wg-down-% to manage interfaces
# - Provides client-list to audit generated client configs
# - Provides client-clean-% to revoke client configs safely
# - Provides client-showqr-% to display QR code for existing client configs (auto-creates missing client)
# - Provides client-dashboard to show emoji table of users/machines vs interfaces
# - Provides wg-clean-% to revoke all clients bound to an interface
# - Provides wg-clean-list-% to preview which client files would be removed by wg-clean-%
#
# USAGE EXAMPLES:
#   make wg7
#       → Create server keypair if missing and write wg7.conf (won't rotate key unless FORCE=1)
#
#   make wg7 CONF_FORCE=1
#       → Rewrite /etc/wireguard/wg7.conf even if it exists
#
#   make wg7 FORCE=1
#       → Regenerate server keypair (will overwrite wg7.key/wg7.pub)
#
#   make client-julie-s22 IFACE=wg7
#       → Generate client config julie-s22-wg7.conf (creates server key if missing, starts wg7)
#
#   make client-julie-s22-wg7
#       → Same as above (name may include -wgN suffix)
#
#   make client-showqr-julie-s22-wg7
#       → Display QR code for julie-s22-wg7 config; auto-create client if missing
#
#   make wg-clean-list-7
#       → Show which client files would be removed for wg7 (preview)
#
#   make wg-clean-7
#       → Remove all client configs/keys for wg7 (revocation)
#
#   make client-list
#       → List all client configs
#
#   make client-clean-julie-s22-wg7
#       → Revoke julie-s22 on wg7 (delete config + keys)
#
#   make client-dashboard
#       → Show emoji table of users/machines vs interfaces
# ============================================================

run_as_root := ./bin/run-as-root
WG_DIR := /etc/wireguard
DNS_SERVER := 10.89.12.4

# -------------------------
# Embedded clients inventory
# -------------------------
# Define clients here as space-separated entries using colon to separate base and iface:
#   <user-machine>:wgN
# Examples:
#   julie-s22:wg7 alice-laptop:wg3 bob-phone:wg7
#
# Edit this variable to add/remove clients. No external clients.list file required.
CLIENTS := \
julie-s22:wg0 \
julie-s22:wg1 \
julie-s22:wg2 \
julie-s22:wg3 \
julie-s22:wg4 \
julie-s22:wg5 \
julie-s22:wg6 \
julie-s22:wg7

.PHONY: ensure-wg-dir wg0 wg1 wg2 wg3 wg4 wg5 wg6 wg7 wg-up-% wg-down-% wg-clean-% wg-clean-list-% client-% client-list client-clean-% client-showqr-% client-dashboard all-wg all-wg-up all-clients-generate wg-add-peers all-start client-dashboard-status

# --- Ensure WG_DIR exists and has correct perms ---
ensure-wg-dir:
	@$(run_as_root) install -d -m 0700 $(WG_DIR)

# --- Server targets (only generate keys when missing; CONF_FORCE to rewrite conf) ---
wg0: ensure-wg-dir
	@echo "[make] Generating WireGuard config for wg0"
	@if [ -f "$(WG_DIR)/wg0.key" ] && [ "$(FORCE)" != "1" ]; then \
		echo "[make] Server key for wg0 already exists, skipping key generation (use FORCE=1 to regenerate)"; \
	else \
		$(run_as_root) bash -c 'wg genkey | tee $(WG_DIR)/wg0.key | wg pubkey > $(WG_DIR)/wg0.pub'; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg0.key $(WG_DIR)/wg0.pub; \
		echo "[make] Server key for wg0 generated"; \
	fi; \
	PORT=51420; IPV4="10.0.0.1/24"; IPV6="fd10:8912:0:10::1/64"; \
	PRIVKEY=$$($(run_as_root) cat $(WG_DIR)/wg0.key); \
	if [ "$(CONF_FORCE)" = "1" ] || [ ! -f "$(WG_DIR)/wg0.conf" ]; then \
		printf "%s\n%s\n%s\n%s\n" \
		"[Interface]" \
		"Address = $$IPV4, $$IPV6" \
		"ListenPort = $$PORT" \
		"PrivateKey = $$PRIVKEY" \
		| $(run_as_root) tee $(WG_DIR)/wg0.conf > /dev/null; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg0.conf; \
		echo "[make] wg0.conf written → $(WG_DIR)/wg0.conf"; \
	else \
		echo "[make] wg0.conf exists and CONF_FORCE!=1, skipping config rewrite"; \
	fi

wg1: ensure-wg-dir
	@echo "[make] Generating WireGuard config for wg1"
	@if [ -f "$(WG_DIR)/wg1.key" ] && [ "$(FORCE)" != "1" ]; then \
		echo "[make] Server key for wg1 already exists, skipping key generation (use FORCE=1 to regenerate)"; \
	else \
		$(run_as_root) bash -c 'wg genkey | tee $(WG_DIR)/wg1.key | wg pubkey > $(WG_DIR)/wg1.pub'; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg1.key $(WG_DIR)/wg1.pub; \
		echo "[make] Server key for wg1 generated"; \
	fi; \
	PORT=51421; IPV4="10.1.0.1/24"; IPV6="fd10:8912:0:11::1/64"; \
	PRIVKEY=$$($(run_as_root) cat $(WG_DIR)/wg1.key); \
	if [ "$(CONF_FORCE)" = "1" ] || [ ! -f "$(WG_DIR)/wg1.conf" ]; then \
		printf "%s\n%s\n%s\n%s\n" \
		"[Interface]" \
		"Address = $$IPV4, $$IPV6" \
		"ListenPort = $$PORT" \
		"PrivateKey = $$PRIVKEY" \
		| $(run_as_root) tee $(WG_DIR)/wg1.conf > /dev/null; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg1.conf; \
		echo "[make] wg1.conf written → $(WG_DIR)/wg1.conf"; \
	else \
		echo "[make] wg1.conf exists and CONF_FORCE!=1, skipping config rewrite"; \
	fi

wg2: ensure-wg-dir
	@echo "[make] Generating WireGuard config for wg2"
	@if [ -f "$(WG_DIR)/wg2.key" ] && [ "$(FORCE)" != "1" ]; then \
		echo "[make] Server key for wg2 already exists, skipping key generation (use FORCE=1 to regenerate)"; \
	else \
		$(run_as_root) bash -c 'wg genkey | tee $(WG_DIR)/wg2.key | wg pubkey > $(WG_DIR)/wg2.pub'; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg2.key $(WG_DIR)/wg2.pub; \
		echo "[make] Server key for wg2 generated"; \
	fi; \
	PORT=51422; IPV4="10.2.0.1/24"; IPV6="fd10:8912:0:12::1/64"; \
	PRIVKEY=$$($(run_as_root) cat $(WG_DIR)/wg2.key); \
	if [ "$(CONF_FORCE)" = "1" ] || [ ! -f "$(WG_DIR)/wg2.conf" ]; then \
		printf "%s\n%s\n%s\n%s\n" \
		"[Interface]" \
		"Address = $$IPV4, $$IPV6" \
		"ListenPort = $$PORT" \
		"PrivateKey = $$PRIVKEY" \
		| $(run_as_root) tee $(WG_DIR)/wg2.conf > /dev/null; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg2.conf; \
		echo "[make] wg2.conf written → $(WG_DIR)/wg2.conf"; \
	else \
		echo "[make] wg2.conf exists and CONF_FORCE!=1, skipping config rewrite"; \
	fi

wg3: ensure-wg-dir
	@echo "[make] Generating WireGuard config for wg3"
	@if [ -f "$(WG_DIR)/wg3.key" ] && [ "$(FORCE)" != "1" ]; then \
		echo "[make] Server key for wg3 already exists, skipping key generation (use FORCE=1 to regenerate)"; \
	else \
		$(run_as_root) bash -c 'wg genkey | tee $(WG_DIR)/wg3.key | wg pubkey > $(WG_DIR)/wg3.pub'; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg3.key $(WG_DIR)/wg3.pub; \
		echo "[make] Server key for wg3 generated"; \
	fi; \
	PORT=51423; IPV4="10.3.0.1/24"; IPV6="fd10:8912:0:13::1/64"; \
	PRIVKEY=$$($(run_as_root) cat $(WG_DIR)/wg3.key); \
	if [ "$(CONF_FORCE)" = "1" ] || [ ! -f "$(WG_DIR)/wg3.conf" ]; then \
		printf "%s\n%s\n%s\n%s\n" \
		"[Interface]" \
		"Address = $$IPV4, $$IPV6" \
		"ListenPort = $$PORT" \
		"PrivateKey = $$PRIVKEY" \
		| $(run_as_root) tee $(WG_DIR)/wg3.conf > /dev/null; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg3.conf; \
		echo "[make] wg3.conf written → $(WG_DIR)/wg3.conf"; \
	else \
		echo "[make] wg3.conf exists and CONF_FORCE!=1, skipping config rewrite"; \
	fi

wg4: ensure-wg-dir
	@echo "[make] Generating WireGuard config for wg4"
	@if [ -f "$(WG_DIR)/wg4.key" ] && [ "$(FORCE)" != "1" ]; then \
		echo "[make] Server key for wg4 already exists, skipping key generation (use FORCE=1 to regenerate)"; \
	else \
		$(run_as_root) bash -c 'wg genkey | tee $(WG_DIR)/wg4.key | wg pubkey > $(WG_DIR)/wg4.pub'; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg4.key $(WG_DIR)/wg4.pub; \
		echo "[make] Server key for wg4 generated"; \
	fi; \
	PORT=51424; IPV4="10.4.0.1/24"; IPV6="fd10:8912:0:14::1/64"; \
	PRIVKEY=$$($(run_as_root) cat $(WG_DIR)/wg4.key); \
	if [ "$(CONF_FORCE)" = "1" ] || [ ! -f "$(WG_DIR)/wg4.conf" ]; then \
		printf "%s\n%s\n%s\n%s\n" \
		"[Interface]" \
		"Address = $$IPV4, $$IPV6" \
		"ListenPort = $$PORT" \
		"PrivateKey = $$PRIVKEY" \
		| $(run_as_root) tee $(WG_DIR)/wg4.conf > /dev/null; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg4.conf; \
		echo "[make] wg4.conf written → $(WG_DIR)/wg4.conf"; \
	else \
		echo "[make] wg4.conf exists and CONF_FORCE!=1, skipping config rewrite"; \
	fi

wg5: ensure-wg-dir
	@echo "[make] Generating WireGuard config for wg5"
	@if [ -f "$(WG_DIR)/wg5.key" ] && [ "$(FORCE)" != "1" ]; then \
		echo "[make] Server key for wg5 already exists, skipping key generation (use FORCE=1 to regenerate)"; \
	else \
		$(run_as_root) bash -c 'wg genkey | tee $(WG_DIR)/wg5.key | wg pubkey > $(WG_DIR)/wg5.pub'; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg5.key $(WG_DIR)/wg5.pub; \
		echo "[make] Server key for wg5 generated"; \
	fi; \
	PORT=51425; IPV4="10.5.0.1/24"; IPV6="fd10:8912:0:15::1/64"; \
	PRIVKEY=$$($(run_as_root) cat $(WG_DIR)/wg5.key); \
	if [ "$(CONF_FORCE)" = "1" ] || [ ! -f "$(WG_DIR)/wg5.conf" ]; then \
		printf "%s\n%s\n%s\n%s\n" \
		"[Interface]" \
		"Address = $$IPV4, $$IPV6" \
		"ListenPort = $$PORT" \
		"PrivateKey = $$PRIVKEY" \
		| $(run_as_root) tee $(WG_DIR)/wg5.conf > /dev/null; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg5.conf; \
		echo "[make] wg5.conf written → $(WG_DIR)/wg5.conf"; \
	else \
		echo "[make] wg5.conf exists and CONF_FORCE!=1, skipping config rewrite"; \
	fi

wg6: ensure-wg-dir
	@echo "[make] Generating WireGuard config for wg6"
	@if [ -f "$(WG_DIR)/wg6.key" ] && [ "$(FORCE)" != "1" ]; then \
		echo "[make] Server key for wg6 already exists, skipping key generation (use FORCE=1 to regenerate)"; \
	else \
		$(run_as_root) bash -c 'wg genkey | tee $(WG_DIR)/wg6.key | wg pubkey > $(WG_DIR)/wg6.pub'; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg6.key $(WG_DIR)/wg6.pub; \
		echo "[make] Server key for wg6 generated"; \
	fi; \
	PORT=51426; IPV4="10.6.0.1/24"; IPV6="fd10:8912:0:16::1/64"; \
	PRIVKEY=$$($(run_as_root) cat $(WG_DIR)/wg6.key); \
	if [ "$(CONF_FORCE)" = "1" ] || [ ! -f "$(WG_DIR)/wg6.conf" ]; then \
		printf "%s\n%s\n%s\n%s\n" \
		"[Interface]" \
		"Address = $$IPV4, $$IPV6" \
		"ListenPort = $$PORT" \
		"PrivateKey = $$PRIVKEY" \
		| $(run_as_root) tee $(WG_DIR)/wg6.conf > /dev/null; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg6.conf; \
		echo "[make] wg6.conf written → $(WG_DIR)/wg6.conf"; \
	else \
		echo "[make] wg6.conf exists and CONF_FORCE!=1, skipping config rewrite"; \
	fi

wg7: ensure-wg-dir
	@echo "[make] Generating WireGuard config for wg7"
	@if [ -f "$(WG_DIR)/wg7.key" ] && [ "$(FORCE)" != "1" ]; then \
		echo "[make] Server key for wg7 already exists, skipping key generation (use FORCE=1 to regenerate)"; \
	else \
		$(run_as_root) bash -c 'wg genkey | tee $(WG_DIR)/wg7.key | wg pubkey > $(WG_DIR)/wg7.pub'; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg7.key $(WG_DIR)/wg7.pub; \
		echo "[make] Server key for wg7 generated"; \
	fi; \
	PORT=51427; IPV4="10.7.0.1/24"; IPV6="fd10:8912:0:17::1/64"; \
	PRIVKEY=$$($(run_as_root) cat $(WG_DIR)/wg7.key); \
	if [ "$(CONF_FORCE)" = "1" ] || [ ! -f "$(WG_DIR)/wg7.conf" ]; then \
		printf "%s\n%s\n%s\n%s\n" \
		"[Interface]" \
		"Address = $$IPV4, $$IPV6" \
		"ListenPort = $$PORT" \
		"PrivateKey = $$PRIVKEY" \
		| $(run_as_root) tee $(WG_DIR)/wg7.conf > /dev/null; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg7.conf; \
		echo "[make] wg7.conf written → $(WG_DIR)/wg7.conf"; \
	else \
		echo "[make] wg7.conf exists and CONF_FORCE!=1, skipping config rewrite"; \
	fi

# --- Named client configs (create only; do NOT print QR) ---
client-%: ensure-wg-dir
	@echo "[make] Generating WireGuard client config for $* (interface $(IFACE))"
	@$(run_as_root) bash -c '\
		BASE="$*"; \
		# prefer explicit IFACE var, else try to extract from name suffix -wgN \
		if [ -z "$(IFACE)" ]; then \
			IFACE=$$(echo "$$BASE" | sed -n "s/.*-\\(wg[0-7]\\)$$/\\1/p"); \
		else \
			IFACE="$(IFACE)"; \
		fi; \
		# determine CONFNAME: if BASE already ends with -wgN use it, otherwise append IFACE \
		if echo "$$BASE" | sed -n "s/.*-wg[0-7]$$/x/p" | grep -q x; then \
			CONFNAME="$$BASE"; \
			[ -z "$$IFACE" ] && IFACE=$$(echo "$$BASE" | sed -n "s/.*-\\(wg[0-7]\\)$$/\\1/p"); \
		else \
			[ -z "$$IFACE" ] && { echo "[make] ❌ must specify IFACE=wgX when client name does not include -wgN"; exit 1; }; \
			CONFNAME="$$BASE-$$IFACE"; \
		fi; \
		# validate IFACE and index \
		IDX=$$(echo "$$IFACE" | sed -n "s/^wg\\([0-7]\\)$$/\\1/p"); \
		[ -n "$$IDX" ] || { echo "[make] ❌ IFACE must be wg0–wg7"; exit 1; }; \
		# ensure server key exists (create and bring up interface if missing) \
		if [ ! -f "$(WG_DIR)/$$IFACE.key" ]; then \
			echo "[make] Server key for $$IFACE not found, generating and bringing interface up..."; \
			wg genkey | tee "$(WG_DIR)/$$IFACE.key" | wg pubkey > "$(WG_DIR)/$$IFACE.pub"; \
			chmod 600 "$(WG_DIR)/$$IFACE.key" "$(WG_DIR)/$$IFACE.pub"; \
			wg-quick up $$IFACE || true; \
		fi; \
		# generate client keypair (skip if exists unless FORCE=1) \
		if [ -f "$(WG_DIR)/$$CONFNAME.key" ] && [ "$(FORCE)" != "1" ]; then \
			echo "[make] Client key for $$CONFNAME already exists, skipping key generation (use FORCE=1 to regenerate)"; \
		else \
			wg genkey | tee "$(WG_DIR)/$$CONFNAME.key" | wg pubkey > "$(WG_DIR)/$$CONFNAME.pub"; \
			chmod 600 "$(WG_DIR)/$$CONFNAME.key" "$(WG_DIR)/$$CONFNAME.pub"; \
		fi; \
		# build config values and write config atomically as root \
		PRIVKEY=$$(cat "$(WG_DIR)/$$CONFNAME.key"); \
		SERVERPUB=$$(cat "$(WG_DIR)/$$IFACE.pub"); \
		PORT=$$(expr 51420 + $$IDX); \
		IPV4="10.$$IDX.0.2/32"; \
		IPV6="fd10:8912:0:1$$IDX::2/128"; \
		# build ALLOWED as a comma-separated list (portable, no leading spaces) \
		ALLOWED_LIST=""; \
		case "$$IDX" in \
			1|3|5|7) ALLOWED_LIST="10.89.12.0/24";; \
		esac; \
		case "$$IDX" in \
			2|3|6|7) \
				if [ -z "$$ALLOWED_LIST" ]; then ALLOWED_LIST="0.0.0.0/0"; else ALLOWED_LIST="$$ALLOWED_LIST, 0.0.0.0/0"; fi;; \
		esac; \
		case "$$IDX" in \
			5|6|7) \
				if [ -z "$$ALLOWED_LIST" ]; then ALLOWED_LIST="::/0"; else ALLOWED_LIST="$$ALLOWED_LIST, ::/0"; fi;; \
		esac; \
		if [ "$$IDX" = "4" ]; then ALLOWED_LIST="fd10:8912:0:14::/64"; fi; \
		ALLOWED="$$ALLOWED_LIST"; \
		printf "%s\n%s\n%s\n%s\n%s\n%s\n%s\n" \
			"[Interface]" \
			"PrivateKey = $$PRIVKEY" \
			"Address = $$IPV4, $$IPV6" \
			"DNS = $(DNS_SERVER)" \
			"" \
			"[Peer]" \
			"PublicKey = $$SERVERPUB" \
			> "$(WG_DIR)/$$CONFNAME.conf"; \
		printf "%s\n%s\n" "Endpoint = vpn.bardi.ch:$$PORT" "AllowedIPs = $$ALLOWED" >> "$(WG_DIR)/$$CONFNAME.conf"; \
		chmod 600 "$(WG_DIR)/$$CONFNAME.conf"; \
		echo "[make] $$CONFNAME.conf written → $(WG_DIR)/$$CONFNAME.conf"; \
	'

# --- Show QR code for existing client config; auto-create if missing (check + display as root) ---
client-showqr-%:
	@echo "[make] Displaying QR code for client $*"
	@CONF="$(WG_DIR)/$*.conf"; \
	if [ -f "$$CONF" ]; then \
		$(run_as_root) qrencode -t ANSIUTF8 < "$$CONF"; \
		exit 0; \
	fi; \
	# parse name: if it ends with -wgN split base/iface, else require IFACE var \
	case "$*" in \
		*-wg[0-7]) \
			BASE=$$(echo "$*" | sed -n 's/^\(.*\)-wg\([0-7]\)$$/\1/p'); \
			IFACE=$$(echo "$*" | sed -n 's/^.*-\(wg[0-7]\)$$/\1/p'); \
			;; \
		*) \
			BASE="$*"; \
			IFACE="$(IFACE)"; \
			;; \
	esac; \
	if [ -z "$$IFACE" ]; then \
		echo "[make] ❌ Config for $* not found and IFACE could not be inferred. Run: make client-<name> IFACE=wgN"; \
		exit 1; \
	fi; \
	CONFNAME="$$BASE-$$IFACE"; \
	echo "[make] Config for $* not found — generating client $$CONFNAME with IFACE=$$IFACE..."; \
	# create client as root (client-% writes the config but does not print QR) \
	$(run_as_root) $(MAKE) client-$$BASE IFACE=$$IFACE || { echo "[make] ❌ Failed to generate client $$CONFNAME"; exit 1; }; \
	# now check existence and display QR as root (same context that created the file) \
	$(run_as_root) sh -c '\
		if [ -f "$(WG_DIR)/'"$$CONFNAME"'.conf" ]; then \
			qrencode -t ANSIUTF8 < "$(WG_DIR)/'"$$CONFNAME"'.conf"; \
		else \
			echo "[make] ❌ Client '"$$CONFNAME"' was not created as expected (root could not find the file)"; \
			exit 1; \
		fi'

# --- Bring up/down any wg interface ---
wg-up-%:
	@echo "[make] Bringing up WireGuard interface wg$*"
	@$(run_as_root) wg-quick up wg$* || { echo "[make] ❌ failed to bring up wg$*"; exit 1; }
	@$(run_as_root) wg show wg$*

wg-down-%:
	@echo "[make] Bringing down WireGuard interface wg$*"
	@$(run_as_root) wg-quick down wg$* || { echo "[make] ❌ failed to bring down wg$*"; exit 1; }

# --- Clean (revoke) all clients bound to an interface (preview) ---
wg-clean-list-%:
	@echo "[make] Clients that would be removed for wg$* (preview):"
	@ls -1 $(WG_DIR)/*-wg$*.conf 2>/dev/null || echo "[make] No client configs found for wg$*."
	@ls -1 $(WG_DIR)/*-wg$*.key 2>/dev/null || true
	@ls -1 $(WG_DIR)/*-wg$*.pub 2>/dev/null || true

# --- Clean (revoke) all clients bound to an interface (destructive, explicit list) ---
wg-clean-%:
	@echo "[make] Revoking all clients bound to wg$*"
	@TO_REMOVE=$$(ls -1 $(WG_DIR)/*-wg$*.conf $(WG_DIR)/*-wg$*.key $(WG_DIR)/*-wg$*.pub 2>/dev/null || true); \
	if [ -z "$$TO_REMOVE" ]; then \
		echo "[make] No client files found for wg$*"; \
	else \
		echo "[make] The following files will be removed:"; \
		printf "%s\n" $$TO_REMOVE; \
		$(run_as_root) sh -c 'rm -f $(WG_DIR)/*-wg$*.conf $(WG_DIR)/*-wg$*.key $(WG_DIR)/*-wg$*.pub'; \
		echo "[make] Removed files:"; \
		printf "%s\n" $$TO_REMOVE; \
	fi

# --- List all client configs ---
client-list:
	@echo "[make] Listing all client configs in $(WG_DIR):"
	@ls -1 $(WG_DIR)/*.conf 2>/dev/null | grep -v 'wg[0-7].conf' || echo "[make] No client configs found."

# --- Clean (revoke) a specific user-machine-interface ---
client-clean-%:
	@echo "[make] Revoking client $*"
	@$(run_as_root) rm -f $(WG_DIR)/$*.conf $(WG_DIR)/$*.key $(WG_DIR)/$*.pub
	@echo "[make] Client $* removed from $(WG_DIR)"

# --- Dashboard: list users, machines, and interfaces (portable, POSIX shell) ---
client-dashboard:
	@echo "| User   | Machine   | wg0 | wg1 | wg2 | wg3 | wg4 | wg5 | wg6 | wg7 |"
	@echo "|--------|-----------|-----|-----|-----|-----|-----|-----|-----|-----|"
	@TMP=$$(mktemp); \
	for f in $(WG_DIR)/*-wg*.conf; do \
		[ -f "$$f" ] || continue; \
		name=$$(basename "$$f" .conf); \
		# strip trailing -wgN to get base "user-machine" \
		base=$$(echo "$$name" | sed -n 's/-wg[0-7]$$//p'); \
		[ -n "$$base" ] && echo "$$base" >> "$$TMP"; \
	done; \
	if [ ! -s "$$TMP" ]; then \
		echo "[make] No client configs found."; rm -f "$$TMP"; exit 0; \
	fi; \
	sort -u "$$TMP" -o "$$TMP"; \
	while read -r base; do \
		# split base into user and machine (first two dash-separated fields) \
		user=$$(echo "$$base" | awk -F- '{print $$1}'); \
		machine=$$(echo "$$base" | awk -F- '{print $$2}'); \
		printf "| %-6s | %-9s |" "$$user" "$$machine"; \
		for i in 0 1 2 3 4 5 6 7; do \
			if [ -f "$(WG_DIR)/$$base-wg$$i.conf" ]; then printf " %s |" "✅"; else printf " %s |" "-"; fi; \
		done; \
		printf "\n"; \
	done < "$$TMP"; \
	rm -f "$$TMP"

# -------------------------
# Bulk orchestration helpers
# -------------------------
ALL_WG := wg0 wg1 wg2 wg3 wg4 wg5 wg6 wg7

.PHONY: all-wg all-wg-up all-clients-generate wg-add-peers all-start client-dashboard-status

# Create server configs for all wg interfaces (uses existing wgN targets)
all-wg: $(ALL_WG)
	@echo "[make] All server configs ensured."

# Bring up all wg interfaces (idempotent)
all-wg-up:
	@echo "[make] Bringing up all wg interfaces..."
	@for i in 0 1 2 3 4 5 6 7; do \
		if [ -f "$(WG_DIR)/wg$$i.conf" ]; then \
			echo "[make] wg-quick up wg$$i"; \
			$(run_as_root) wg-quick up wg$$i || echo "[make] wg$$i already up or failed to start"; \
		else \
			echo "[make] skipping wg$$i (no config)"; \
		fi; \
	done

# Generate all missing client keys/configs from embedded CLIENTS variable
all-clients-generate:
	@echo "[make] Generating all missing client keys/configs from CLIENTS variable..."
	@for entry in $(CLIENTS); do \
		# entry format base:iface \
		base=$$(echo $$entry | sed 's/:.*//'); \
		iface=$$(echo $$entry | sed 's/.*://'); \
		if [ -z "$$base" ] || [ -z "$$iface" ]; then \
			echo "[make] ❌ skipping $$entry — invalid format (expected base:wgN)"; continue; \
		fi; \
		CONFNAME="$$base-$$iface"; \
		if [ ! -f "$(WG_DIR)/$$CONFNAME.conf" ] || [ ! -f "$(WG_DIR)/$$CONFNAME.key" ]; then \
			echo "[make] Creating $$CONFNAME (IFACE=$$iface)"; \
			$(run_as_root) $(MAKE) client-$$base IFACE=$$iface || { echo "[make] ❌ failed to create $$CONFNAME"; exit 1; }; \
		else \
			echo "[make] $$CONFNAME already exists, skipping"; \
		fi; \
	done; \
	echo "[make] client generation complete."

# Ensure each server config contains persistent [Peer] blocks for clients and reload interfaces
wg-add-peers:
	@echo "[make] Ensuring peers are present in server configs (from CLIENTS variable)..."
	@for entry in $(CLIENTS); do \
		base=$$(echo $$entry | sed 's/:.*//'); \
		iface=$$(echo $$entry | sed 's/.*://'); \
		if [ -z "$$base" ] || [ -z "$$iface" ]; then \
			echo "[make] ❌ skipping $$entry — invalid format"; continue; \
		fi; \
		CONFNAME="$$base-$$iface"; \
		CLIENT_PUB="$(WG_DIR)/$$CONFNAME.pub"; \
		SERVER_CONF="$(WG_DIR)/$$iface.conf"; \
		if [ ! -f "$$CLIENT_PUB" ]; then echo "[make] ❌ missing $$CLIENT_PUB, skipping"; continue; fi; \
		if [ ! -f "$$SERVER_CONF" ]; then echo "[make] ❌ missing $$SERVER_CONF, skipping"; continue; fi; \
		PUB=$$(cat "$$CLIENT_PUB"); \
		# skip if public key already present in server config
		grep -qF "$$PUB" "$$SERVER_CONF" 2>/dev/null && { echo "[make] $$CONFNAME already present in $$SERVER_CONF, skipping"; continue; }; \
		echo "[make] Adding peer $$CONFNAME to $$SERVER_CONF"; \
		# compute Allowed IP (first address from client config)
		ALLOWED_IP=$$(grep -E '^Address' $(WG_DIR)/$$CONFNAME.conf 2>/dev/null | sed -n 's/Address = //p' | awk -F, '{print $$1}' | sed -n 's/^[[:space:]]*//;s/[[:space:]]*$$//p'); \
		[ -z "$$ALLOWED_IP" ] && ALLOWED_IP="0.0.0.0/0"; \
		# add peer to running interface (best-effort)
		$(run_as_root) wg set $$iface peer "$$PUB" allowed-ips "$$ALLOWED_IP" || true; \
		# append a clean peer block to the server config as root
		printf "\n[Peer]\n# %s\nPublicKey = %s\nAllowedIPs = %s\n" "$$CONFNAME" "$$PUB" "$$ALLOWED_IP" | $(run_as_root) tee -a "$$SERVER_CONF" > /dev/null; \
		# reload interface to ensure runtime matches file
		echo "[make] Reloading $$iface"; \
		$(run_as_root) wg-quick down $$iface || true; \
		$(run_as_root) wg-quick up $$iface || true; \
	done; \
	echo "[make] wg-add-peers complete."



# Full start: create servers, bring them up, create clients, add peers, and show dashboard
all-start: all-wg all-wg-up all-clients-generate wg-add-peers client-dashboard-status
	@echo "[make] all-start complete."

# Dashboard with server status and client online state (handshake) — prints a compact table
client-dashboard-status:
	@echo "| Interface | Status | ListenPort | Peers (online/total) |"; \
	echo "|-----------|--------|------------|----------------------|"; \
	for i in 0 1 2 3 4 5 6 7; do \
		if [ -f "$(WG_DIR)/wg$$i.conf" ]; then \
			if ip link show wg$$i >/dev/null 2>&1; then STATUS="up"; else STATUS="down"; fi; \
			LPORT=$$(grep -E '^ListenPort' $(WG_DIR)/wg$$i.conf 2>/dev/null | sed -n 's/ListenPort = //p' || echo "-"); \
			TOTAL=$$(awk '$$1=="[Peer]"{c++}END{print (c+0)}' $(WG_DIR)/wg$$i.conf 2>/dev/null | tr -d ' '); \
			ONLINE=0; \
			if ip link show wg$$i >/dev/null 2>&1; then \
				HANDSHAKES=$$(wg show wg$$i 2>/dev/null | awk '/latest handshake/ && $$0 !~ /0s/ {count++} END {print (count+0)}'); \
				if [ "$$HANDSHAKES" -gt 0 ]; then ONLINE="$$HANDSHAKES"; else ONLINE=$$(wg show wg$$i peers 2>/dev/null | wc -l | tr -d ' '); fi; \
			fi; \
			printf "| %-9s | %-6s | %-10s | %3s/%-3s |\n" "wg$$i" "$$STATUS" "$$LPORT" "$$ONLINE" "$$TOTAL"; \
		else \
			printf "| %-9s | %-6s | %-10s | %3s/%-3s |\n" "wg$$i" "missing" "-" "0" "0"; \
		fi; \
	done


# Backwards-compatible client-dashboard (human readable) calls the status target
client-dashboard: client-dashboard-status
