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

# Absolute paths to WireGuard binaries to avoid PATH issues under sudo/run-as-root
WG_BIN := /usr/bin/wg
WG_QUICK := /usr/bin/wg-quick

# Avoid recursive-make "Entering directory" messages
MAKEFLAGS += --no-print-directory

# export FORCE and CONF_FORCE so recursive make inherits them
export FORCE CONF_FORCE

# NOTE: Some recipes invoke a root-owned make via $(run_as_root) $(MAKE) ...
# To guarantee that FORCE and CONF_FORCE are visible to the recursive root
# make process we explicitly wrap recursive invocations in a shell under
# run-as-root so environment assignments are evaluated by the shell and
# not interpreted as separate commands by sudo-like helpers.

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

.PHONY: ensure-wg-dir wg0 wg1 wg2 wg3 wg4 wg5 wg6 wg7 wg-up-% wg-down-% wg-clean-% wg-clean-list-% client-% client-list client-clean-% client-showqr-% client-dashboard all-wg all-wg-up all-clients-generate wg-add-peers all-start client-dashboard-status regen-clients

# --- Ensure WG_DIR exists and has correct perms ---
ensure-wg-dir:
	@$(run_as_root) install -d -m 0700 $(WG_DIR)

# --- Server targets (only generate keys when missing; CONF_FORCE to rewrite conf) ---
wg0: ensure-wg-dir
	@echo "🔧 Generating WireGuard config for wg0"
	@if [ -f "$(WG_DIR)/wg0.key" ] && [ "$(FORCE)" != "1" ]; then \
		echo "🔒 Server key for wg0 already exists, skipping key generation (use FORCE=1 to regenerate)"; \
	else \
		$(run_as_root) sh -c '$(WG_BIN) genkey | tee $(WG_DIR)/wg0.key | $(WG_BIN) pubkey > $(WG_DIR)/wg0.pub'; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg0.key $(WG_DIR)/wg0.pub; \
		echo "✅ Server key for wg0 generated"; \
	fi; \
	PORT=51420; IPV4="10.0.0.1/24"; IPV6="2a01:8b81:4800:9c00:10::1/64"; \
	PRIVKEY=$$($(run_as_root) cat $(WG_DIR)/wg0.key); \
	if [ "$(CONF_FORCE)" = "1" ] || [ ! -f "$(WG_DIR)/wg0.conf" ]; then \
		printf "%s\n%s\n%s\n%s\n" \
		"[Interface]" \
		"Address = $$IPV4, $$IPV6" \
		"ListenPort = $$PORT" \
		"PrivateKey = $$PRIVKEY" \
		| $(run_as_root) tee $(WG_DIR)/wg0.conf > /dev/null; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg0.conf; \
		echo "📄 wg0.conf written → $(WG_DIR)/wg0.conf"; \
		$(run_as_root) sh -c 'FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) $(MAKE) regen-clients IFACE=wg0' || echo "⚠️  regen-clients failed for wg0"; \
	else \
		echo "⏭ wg0.conf exists and CONF_FORCE!=1, skipping config rewrite"; \
	fi

wg1: ensure-wg-dir
	@echo "🔧 Generating WireGuard config for wg1"
	@if [ -f "$(WG_DIR)/wg1.key" ] && [ "$(FORCE)" != "1" ]; then \
		echo "🔒 Server key for wg1 already exists, skipping key generation (use FORCE=1 to regenerate)"; \
	else \
		$(run_as_root) sh -c '$(WG_BIN) genkey | tee $(WG_DIR)/wg1.key | $(WG_BIN) pubkey > $(WG_DIR)/wg1.pub'; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg1.key $(WG_DIR)/wg1.pub; \
		echo "✅ Server key for wg1 generated"; \
	fi; \
	PORT=51421; IPV4="10.1.0.1/24"; IPV6="2a01:8b81:4800:9c00:11::1/64"; \
	PRIVKEY=$$($(run_as_root) cat $(WG_DIR)/wg1.key); \
	if [ "$(CONF_FORCE)" = "1" ] || [ ! -f "$(WG_DIR)/wg1.conf" ]; then \
		printf "%s\n%s\n%s\n%s\n" \
		"[Interface]" \
		"Address = $$IPV4, $$IPV6" \
		"ListenPort = $$PORT" \
		"PrivateKey = $$PRIVKEY" \
		| $(run_as_root) tee $(WG_DIR)/wg1.conf > /dev/null; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg1.conf; \
		echo "📄 wg1.conf written → $(WG_DIR)/wg1.conf"; \
		$(run_as_root) sh -c 'FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) $(MAKE) regen-clients IFACE=wg1' || echo "⚠️  regen-clients failed for wg1"; \
	else \
		echo "⏭ wg1.conf exists and CONF_FORCE!=1, skipping config rewrite"; \
	fi

wg2: ensure-wg-dir
	@echo "🔧 Generating WireGuard config for wg2"
	@if [ -f "$(WG_DIR)/wg2.key" ] && [ "$(FORCE)" != "1" ]; then \
		echo "🔒 Server key for wg2 already exists, skipping key generation (use FORCE=1 to regenerate)"; \
	else \
		$(run_as_root) sh -c '$(WG_BIN) genkey | tee $(WG_DIR)/wg2.key | $(WG_BIN) pubkey > $(WG_DIR)/wg2.pub'; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg2.key $(WG_DIR)/wg2.pub; \
		echo "✅ Server key for wg2 generated"; \
	fi; \
	PORT=51422; IPV4="10.2.0.1/24"; IPV6="2a01:8b81:4800:9c00:12::1/64"; \
	PRIVKEY=$$($(run_as_root) cat $(WG_DIR)/wg2.key); \
	if [ "$(CONF_FORCE)" = "1" ] || [ ! -f "$(WG_DIR)/wg2.conf" ]; then \
		printf "%s\n%s\n%s\n%s\n" \
		"[Interface]" \
		"Address = $$IPV4, $$IPV6" \
		"ListenPort = $$PORT" \
		"PrivateKey = $$PRIVKEY" \
		| $(run_as_root) tee $(WG_DIR)/wg2.conf > /dev/null; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg2.conf; \
		echo "📄 wg2.conf written → $(WG_DIR)/wg2.conf"; \
		$(run_as_root) sh -c 'FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) $(MAKE) regen-clients IFACE=wg2' || echo "⚠️  regen-clients failed for wg2"; \
	else \
		echo "⏭ wg2.conf exists and CONF_FORCE!=1, skipping config rewrite"; \
	fi

wg3: ensure-wg-dir
	@echo "🔧 Generating WireGuard config for wg3"
	@if [ -f "$(WG_DIR)/wg3.key" ] && [ "$(FORCE)" != "1" ]; then \
		echo "🔒 Server key for wg3 already exists, skipping key generation (use FORCE=1 to regenerate)"; \
	else \
		$(run_as_root) sh -c '$(WG_BIN) genkey | tee $(WG_DIR)/wg3.key | $(WG_BIN) pubkey > $(WG_DIR)/wg3.pub'; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg3.key $(WG_DIR)/wg3.pub; \
		echo "✅ Server key for wg3 generated"; \
	fi; \
	PORT=51423; IPV4="10.3.0.1/24"; IPV6="2a01:8b81:4800:9c00:13::1/64"; \
	PRIVKEY=$$($(run_as_root) cat $(WG_DIR)/wg3.key); \
	if [ "$(CONF_FORCE)" = "1" ] || [ ! -f "$(WG_DIR)/wg3.conf" ]; then \
		printf "%s\n%s\n%s\n%s\n" \
		"[Interface]" \
		"Address = $$IPV4, $$IPV6" \
		"ListenPort = $$PORT" \
		"PrivateKey = $$PRIVKEY" \
		| $(run_as_root) tee $(WG_DIR)/wg3.conf > /dev/null; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg3.conf; \
		echo "📄 wg3.conf written → $(WG_DIR)/wg3.conf"; \
		$(run_as_root) sh -c 'FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) $(MAKE) regen-clients IFACE=wg3' || echo "⚠️  regen-clients failed for wg3"; \
	else \
		echo "⏭ wg3.conf exists and CONF_FORCE!=1, skipping config rewrite"; \
	fi

wg4: ensure-wg-dir
	@echo "🔧 Generating WireGuard config for wg4"
	@if [ -f "$(WG_DIR)/wg4.key" ] && [ "$(FORCE)" != "1" ]; then \
		echo "🔒 Server key for wg4 already exists, skipping key generation (use FORCE=1 to regenerate)"; \
	else \
		$(run_as_root) sh -c '$(WG_BIN) genkey | tee $(WG_DIR)/wg4.key | $(WG_BIN) pubkey > $(WG_DIR)/wg4.pub'; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg4.key $(WG_DIR)/wg4.pub; \
		echo "✅ Server key for wg4 generated"; \
	fi; \
	PORT=51424; IPV4="10.4.0.1/24"; IPV6="2a01:8b81:4800:9c00:14::1/64"; \
	PRIVKEY=$$($(run_as_root) cat $(WG_DIR)/wg4.key); \
	if [ "$(CONF_FORCE)" = "1" ] || [ ! -f "$(WG_DIR)/wg4.conf" ]; then \
		printf "%s\n%s\n%s\n%s\n" \
		"[Interface]" \
		"Address = $$IPV4, $$IPV6" \
		"ListenPort = $$PORT" \
		"PrivateKey = $$PRIVKEY" \
		| $(run_as_root) tee $(WG_DIR)/wg4.conf > /dev/null; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg4.conf; \
		echo "📄 wg4.conf written → $(WG_DIR)/wg4.conf"; \
		$(run_as_root) sh -c 'FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) $(MAKE) regen-clients IFACE=wg4' || echo "⚠️  regen-clients failed for wg4"; \
	else \
		echo "⏭ wg4.conf exists and CONF_FORCE!=1, skipping config rewrite"; \
	fi

wg5: ensure-wg-dir
	@echo "🔧 Generating WireGuard config for wg5"
	@if [ -f "$(WG_DIR)/wg5.key" ] && [ "$(FORCE)" != "1" ]; then \
		echo "🔒 Server key for wg5 already exists, skipping key generation (use FORCE=1 to regenerate)"; \
	else \
		$(run_as_root) sh -c '$(WG_BIN) genkey | tee $(WG_DIR)/wg5.key | $(WG_BIN) pubkey > $(WG_DIR)/wg5.pub'; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg5.key $(WG_DIR)/wg5.pub; \
		echo "✅ Server key for wg5 generated"; \
	fi; \
	PORT=51425; IPV4="10.5.0.1/24"; IPV6="2a01:8b81:4800:9c00:15::1/64"; \
	PRIVKEY=$$($(run_as_root) cat $(WG_DIR)/wg5.key); \
	if [ "$(CONF_FORCE)" = "1" ] || [ ! -f "$(WG_DIR)/wg5.conf" ]; then \
		printf "%s\n%s\n%s\n%s\n" \
		"[Interface]" \
		"Address = $$IPV4, $$IPV6" \
		"ListenPort = $$PORT" \
		"PrivateKey = $$PRIVKEY" \
		| $(run_as_root) tee $(WG_DIR)/wg5.conf > /dev/null; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg5.conf; \
		echo "📄 wg5.conf written → $(WG_DIR)/wg5.conf"; \
		$(run_as_root) sh -c 'FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) $(MAKE) regen-clients IFACE=wg5' || echo "⚠️  regen-clients failed for wg5"; \
	else \
		echo "⏭ wg5.conf exists and CONF_FORCE!=1, skipping config rewrite"; \
	fi

wg6: ensure-wg-dir
	@echo "🔧 Generating WireGuard config for wg6"
	@if [ -f "$(WG_DIR)/wg6.key" ] && [ "$(FORCE)" != "1" ]; then \
		echo "🔒 Server key for wg6 already exists, skipping key generation (use FORCE=1 to regenerate)"; \
	else \
		$(run_as_root) sh -c '$(WG_BIN) genkey | tee $(WG_DIR)/wg6.key | $(WG_BIN) pubkey > $(WG_DIR)/wg6.pub'; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg6.key $(WG_DIR)/wg6.pub; \
		echo "✅ Server key for wg6 generated"; \
	fi; \
	PORT=51426; IPV4="10.6.0.1/24"; IPV6="2a01:8b81:4800:9c00:16::1/64"; \
	PRIVKEY=$$($(run_as_root) cat $(WG_DIR)/wg6.key); \
	if [ "$(CONF_FORCE)" = "1" ] || [ ! -f "$(WG_DIR)/wg6.conf" ]; then \
		printf "%s\n%s\n%s\n%s\n" \
		"[Interface]" \
		"Address = $$IPV4, $$IPV6" \
		"ListenPort = $$PORT" \
		"PrivateKey = $$PRIVKEY" \
		| $(run_as_root) tee $(WG_DIR)/wg6.conf > /dev/null; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg6.conf; \
		echo "📄 wg6.conf written → $(WG_DIR)/wg6.conf"; \
		$(run_as_root) sh -c 'FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) $(MAKE) regen-clients IFACE=wg6' || echo "⚠️  regen-clients failed for wg6"; \
	else \
		echo "⏭ wg6.conf exists and CONF_FORCE!=1, skipping config rewrite"; \
	fi

wg7: ensure-wg-dir
	@echo "🔧 Generating WireGuard config for wg7"
	@if [ -f "$(WG_DIR)/wg7.key" ] && [ "$(FORCE)" != "1" ]; then \
		echo "🔒 Server key for wg7 already exists, skipping key generation (use FORCE=1 to regenerate)"; \
	else \
		$(run_as_root) sh -c '$(WG_BIN) genkey | tee $(WG_DIR)/wg7.key | $(WG_BIN) pubkey > $(WG_DIR)/wg7.pub'; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg7.key $(WG_DIR)/wg7.pub; \
		echo "✅ Server key for wg7 generated"; \
	fi; \
	PORT=51427; IPV4="10.7.0.1/24"; IPV6="2a01:8b81:4800:9c00:17::1/64"; \
	PRIVKEY=$$($(run_as_root) cat $(WG_DIR)/wg7.key); \
	if [ "$(CONF_FORCE)" = "1" ] || [ ! -f "$(WG_DIR)/wg7.conf" ]; then \
		printf "%s\n%s\n%s\n%s\n" \
		"[Interface]" \
		"Address = $$IPV4, $$IPV6" \
		"ListenPort = $$PORT" \
		"PrivateKey = $$PRIVKEY" \
		| $(run_as_root) tee $(WG_DIR)/wg7.conf > /dev/null; \
		$(run_as_root) chmod 600 $(WG_DIR)/wg7.conf; \
		echo "📄 wg7.conf written → $(WG_DIR)/wg7.conf"; \
		$(run_as_root) sh -c 'FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) $(MAKE) regen-clients IFACE=wg7' || echo "⚠️  regen-clients failed for wg7"; \
	else \
		echo "⏭ wg7.conf exists and CONF_FORCE!=1, skipping config rewrite"; \
	fi

# --- Named client configs (create only; do NOT print QR) ---
client-%: ensure-wg-dir
	@echo "🧩 Generating WireGuard client config for $* (interface $(IFACE))"
	@$(run_as_root) sh -c '\
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
			[ -z "$$IFACE" ] && { echo "❌ must specify IFACE=wgX when client name does not include -wgN"; exit 1; }; \
			CONFNAME="$$BASE-$$IFACE"; \
		fi; \
		# validate IFACE and index \
		IDX=$$(echo "$$IFACE" | sed -n "s/^wg\\([0-7]\\)$$/\\1/p"); \
		[ -n "$$IDX" ] || { echo "❌ IFACE must be wg0–wg7"; exit 1; }; \
		# ensure server key exists (create and bring up interface if missing) \
		if [ ! -f "$(WG_DIR)/$$IFACE.key" ]; then \
			echo "⚠️  Server key for $$IFACE not found, generating and bringing interface up..."; \
			$(WG_BIN) genkey | tee "$(WG_DIR)/$$IFACE.key" | $(WG_BIN) pubkey > "$(WG_DIR)/$$IFACE.pub"; \
			chmod 600 "$(WG_DIR)/$$IFACE.key" "$(WG_DIR)/$$IFACE.pub"; \
			$(WG_QUICK) up $$IFACE || true; \
		fi; \
		# generate client keypair (skip if exists unless FORCE=1) \
		if [ -f "$(WG_DIR)/$$CONFNAME.key" ] && [ "$(FORCE)" != "1" ]; then \
			echo "🔒 Client key for $$CONFNAME already exists, skipping key generation (use FORCE=1 to regenerate)"; \
			# ensure pub exists when key already present \
			if [ ! -f "$(WG_DIR)/$$CONFNAME.pub" ]; then \
				echo "ℹ️  Client pub for $$CONFNAME missing — generating from key"; \
				$(WG_BIN) pubkey < "$(WG_DIR)/$$CONFNAME.key" > "$(WG_DIR)/$$CONFNAME.pub" || true; \
				chmod 600 "$(WG_DIR)/$$CONFNAME.pub" || true; \
			fi; \
		else \
			$(WG_BIN) genkey | tee "$(WG_DIR)/$$CONFNAME.key" | $(WG_BIN) pubkey > "$(WG_DIR)/$$CONFNAME.pub"; \
			chmod 600 "$(WG_DIR)/$$CONFNAME.key" "$(WG_DIR)/$$CONFNAME.pub"; \
		fi; \
		# build config values and write config atomically as root \
		PRIVKEY=$$(cat "$(WG_DIR)/$$CONFNAME.key"); \
		SERVERPUB=$$(cat "$(WG_DIR)/$$IFACE.pub"); \
		PORT=$$(expr 51420 + $$IDX); \
		IPV4="10.$$IDX.0.2/32"; \
		IPV6="2a01:8b81:4800:9c00:1$$IDX::2/128"; \
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
		if [ "$$IDX" = "4" ]; then ALLOWED_LIST="2a01:8b81:4800:9c00:14::/64"; fi; \
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
		# write Endpoint and only write AllowedIPs if non-empty \
		if [ -n "$$ALLOWED" ]; then \
			printf "%s\n%s\n%s\n" "Endpoint = vpn.bardi.ch:$$PORT" "PersistentKeepalive = 25" "AllowedIPs = $$ALLOWED" >> "$(WG_DIR)/$$CONFNAME.conf"; \
		else \
			printf "%s\n%s\n" "Endpoint = vpn.bardi.ch:$$PORT" "PersistentKeepalive = 25" >> "$(WG_DIR)/$$CONFNAME.conf"; \
		fi; \
		chmod 600 "$(WG_DIR)/$$CONFNAME.conf"; \
		echo "✅ $$CONFNAME.conf written → $(WG_DIR)/$$CONFNAME.conf"; \
	'

# --- Show QR code for existing client config; auto-create if missing (check + display as root) ---
client-showqr-%:
	@echo "🔍 Displaying QR code for client $*"
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
		echo "❌ Config for $* not found and IFACE could not be inferred. Run: make client-<name> IFACE=wgN"; \
		exit 1; \
	fi; \
	CONFNAME="$$BASE-$$IFACE"; \
	echo "ℹ️  Config for $* not found — generating client $$CONFNAME with IFACE=$$IFACE..."; \
	# create client as root (client-% writes the config but does not print QR) \
	$(run_as_root) sh -c 'FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) $(MAKE) client-'"$$BASE"' IFACE='"$$IFACE"'' || { echo "❌ Failed to generate client $$CONFNAME"; exit 1; }; \
	# now check existence and display QR as root (same context that created the file) \
	$(run_as_root) sh -c '\
		if [ -f "$(WG_DIR)/'"$$CONFNAME"'.conf" ]; then \
			qrencode -t ANSIUTF8 < "$(WG_DIR)/'"$$CONFNAME"'.conf"; \
		else \
			echo "❌ Client '"$$CONFNAME"' was not created as expected (root could not find the file)"; \
			exit 1; \
		fi'

# --- Bring up/down any wg interface ---
wg-up-%:
	@echo "⏫ Bringing up WireGuard interface wg$*"
	@$(run_as_root) $(WG_QUICK) up wg$* || { echo "❌ failed to bring up wg$*"; exit 1; }
	@$(run_as_root) $(WG_BIN) show wg$*

wg-down-%:
	@echo "⏬ Bringing down WireGuard interface wg$*"
	@$(run_as_root) $(WG_QUICK) down wg$* || { echo "❌ failed to bring down wg$*"; exit 1; }

# --- Clean (revoke) all clients bound to an interface (preview) ---
wg-clean-list-%:
	@echo "🗑️  Clients that would be removed for wg$* (preview):"
	@ls -1 $(WG_DIR)/*-wg$*.conf 2>/dev/null || echo "⏭ No client configs found for wg$*."
	@ls -1 $(WG_DIR)/*-wg$*.key 2>/dev/null || true
	@ls -1 $(WG_DIR)/*-wg$*.pub 2>/dev/null || true

# --- Clean (revoke) all clients bound to an interface (destructive, explicit list) ---
wg-clean-%:
	@echo "🧹 Revoking all clients bound to wg$*"
	@TO_REMOVE=$$(ls -1 $(WG_DIR)/*-wg$*.conf $(WG_DIR)/*-wg$*.key $(WG_DIR)/*-wg$*.pub 2>/dev/null || true); \
	if [ -z "$$TO_REMOVE" ]; then \
		echo "⏭ No client files found for wg$*"; \
	else \
		echo "⚠️  The following files will be removed:"; \
		printf "%s\n" $$TO_REMOVE; \
		$(run_as_root) sh -c 'rm -f $(WG_DIR)/*-wg$*.conf $(WG_DIR)/*-wg$*.key $(WG_DIR)/*-wg$*.pub'; \
		echo "✅ Removed files:"; \
		printf "%s\n" $$TO_REMOVE; \
	fi

# --- List all client configs ---
client-list:
	@echo "📋 Listing all client configs in $(WG_DIR):"
	@ls -1 $(WG_DIR)/*.conf 2>/dev/null | grep -v 'wg[0-7].conf' || echo "⏭ No client configs found."

# --- Clean (revoke) a specific user-machine-interface ---
client-clean-%:
	@echo "🧾 Revoking client $*"
	@$(run_as_root) rm -f $(WG_DIR)/$*.conf $(WG_DIR)/$*.key $(WG_DIR)/$*.pub
	@echo "✅ Client $* removed from $(WG_DIR)"

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
		echo "⏭ No client configs found."; rm -f "$$TMP"; exit 0; \
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
	@echo "✅ All server configs ensured."

# Bring up all wg interfaces (idempotent)
all-wg-up:
	@echo "⏫ Bringing up all wg interfaces..."
	@for i in 0 1 2 3 4 5 6 7; do \
		if [ -f "$(WG_DIR)/wg$$i.conf" ]; then \
			echo "⏫ wg-quick up wg$$i"; \
			$(run_as_root) $(WG_QUICK) up wg$$i || echo "⚠️  wg$$i already up or failed to start"; \
		else \
			echo "⏭ skipping wg$$i (no config)"; \
		fi; \
	done

# Generate all missing client keys/configs from embedded CLIENTS variable
all-clients-generate:
	@echo "🛠️  Generating all missing client keys/configs from CLIENTS variable..."
	@for entry in $(CLIENTS); do \
		# entry format base:iface \
		base=$$(echo $$entry | sed 's/:.*//'); \
		iface=$$(echo $$entry | sed 's/.*://'); \
		if [ -z "$$base" ] || [ -z "$$iface" ]; then \
			echo "❌ skipping $$entry — invalid format (expected base:wgN)"; continue; \
		fi; \
		CONFNAME="$$base-$$iface"; \
		if [ ! -f "$(WG_DIR)/$$CONFNAME.conf" ] || [ ! -f "$(WG_DIR)/$$CONFNAME.key" ]; then \
			echo "➕ Creating $$CONFNAME (IFACE=$$iface)"; \
			$(run_as_root) sh -c 'FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) $(MAKE) client-'"$$base"' IFACE='"$$iface"'' || { echo "❌ failed to create $$CONFNAME"; exit 1; }; \
		else \
			echo "✅ $$CONFNAME already exists, skipping"; \
		fi; \
	done; \
	echo "✅ client generation complete."

# Ensure each server config contains persistent [Peer] blocks for clients and reload interfaces
wg-add-peers:
	@echo "🔗 Ensuring peers are present in server configs (from CLIENTS variable)..."
	@$(run_as_root) sh -c '\
		CLIENTS="$(CLIENTS)"; \
		for entry in $$CLIENTS; do \
			base=$$(echo $$entry | sed "s/:.*//"); \
			iface=$$(echo $$entry | sed "s/.*://"); \
			CONFNAME="$$base-$$iface"; \
			CLIENT_PUB="$(WG_DIR)/$$CONFNAME.pub"; \
			SERVER_CONF="$(WG_DIR)/$$iface.conf"; \
			if [ ! -f "$$CLIENT_PUB" ] && [ -f "$(WG_DIR)/$$CONFNAME.key" ]; then \
				echo "ℹ️  Generating pub for $$CONFNAME"; \
				$(WG_BIN) pubkey < "$(WG_DIR)/$$CONFNAME.key" > "$$CLIENT_PUB"; \
				chmod 600 "$$CLIENT_PUB"; \
			fi; \
			[ -f "$$CLIENT_PUB" ] || { echo "❌ missing $$CLIENT_PUB, skipping"; continue; }; \
			[ -f "$$SERVER_CONF" ] || { echo "❌ missing $$SERVER_CONF, skipping"; continue; }; \
			PUB=$$(cat "$$CLIENT_PUB"); \
			grep -qF "$$PUB" "$$SERVER_CONF" && { echo "✅ $$CONFNAME already present, skipping"; continue; }; \
			# extract client addresses (Address lines) to use as AllowedIPs on server side \
			ALLOWED_IPS=$$(grep -E "^Address" "$(WG_DIR)/$$CONFNAME.conf" | sed "s/Address = //"); \
			echo "➕ Adding peer $$CONFNAME to $$SERVER_CONF"; \
			$(WG_BIN) set $$iface peer "$$PUB" allowed-ips "$$ALLOWED_IPS" || true; \
			printf "\n[Peer]\n# %s\nPublicKey = %s\nAllowedIPs = %s\n" "$$CONFNAME" "$$PUB" "$$ALLOWED_IPS" | tee -a "$$SERVER_CONF" > /dev/null; \
			echo "🔁 Reloading $$iface"; \
			$(WG_QUICK) down $$iface || true; \
			$(WG_QUICK) up $$iface || true; \
		done; \
		echo "✅ wg-add-peers complete."'



.PHONY: regen-clients
# Regenerate client configs for the interface named in $(IFACE)
regen-clients:
	@if [ -z "$(IFACE)" ]; then \
		echo "❌ regen-clients requires IFACE=wgN"; exit 1; \
	fi; \
	echo "♻️  Regenerating client configs for $(IFACE) (FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE))"; \
	for entry in $(CLIENTS); do \
		base=$$(echo $$entry | sed 's/:.*//'); \
		iface=$$(echo $$entry | sed 's/.*://'); \
		if [ "$$iface" = "$(IFACE)" ]; then \
			echo "🔁 Regenerating client $$base for $(IFACE)"; \
			$(run_as_root) sh -c 'FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) $(MAKE) client-'"$$base"' IFACE='"$(IFACE)"'' || echo "⚠️  failed to regenerate $$base"; \
		fi; \
	done; \
	echo "✅ regen-clients complete for $(IFACE)";

# Full start: create servers, bring them up, create clients, add peers, and show dashboard
all-start: all-wg all-wg-up all-clients-generate wg-add-peers client-dashboard-status
	@echo "✅ all-start complete."

# Dashboard with server status and client online state (handshake) — prints a compact table
client-dashboard-status:
	@echo "| Interface | Status | ListenPort | Peers (online/total) |"; \
	echo "|-----------|--------|------------|----------------------|"; \
	for i in 0 1 2 3 4 5 6 7; do \
		if $(run_as_root) test -f $(WG_DIR)/wg$$i.conf; then \
			if $(run_as_root) ip link show wg$$i >/dev/null 2>&1; then STATUS="up"; else STATUS="down"; fi; \
			LPORT=$$($(run_as_root) awk -F' = ' '/^ListenPort/ {print $$2; exit}' $(WG_DIR)/wg$$i.conf 2>/dev/null || echo "-"); \
			TOTAL=$$($(run_as_root) awk '$$1=="[Peer]"{c++}END{print (c+0)}' $(WG_DIR)/wg$$i.conf 2>/dev/null | tr -d ' '); \
			ONLINE=0; \
			if $(run_as_root) ip link show wg$$i >/dev/null 2>&1; then \
				HANDSHAKES=$$($(run_as_root) sh -c '$(WG_BIN) show wg'"$$i"' 2>/dev/null' | awk '/latest handshake/ && $$0 !~ /0s/ {count++} END {print (count+0)}'); \
				if [ "$$HANDSHAKES" -gt 0 ]; then ONLINE="$$HANDSHAKES"; else ONLINE=$$($(run_as_root) sh -c '$(WG_BIN) show wg'"$$i"' peers 2>/dev/null' | wc -l | tr -d ' '); fi; \
			fi; \
			printf "| %-9s | %-6s | %-10s | %3s/%-3s |\n" "wg$$i" "$$STATUS" "$$LPORT" "$$ONLINE" "$$TOTAL"; \
		else \
			printf "| %-9s | %-6s | %-10s | %3s/%-3s |\n" "wg$$i" "missing" "-" "0" "0"; \
		fi; \
	done

# Backwards-compatible client-dashboard (human readable) calls the status target
client-dashboard: client-dashboard-status

.PHONY: regen-all-keys
regen-all-keys:
	@echo "== regen-all-keys: backup /etc/wireguard and rotate keys =="
	@echo "Backing up /etc/wireguard to /root/wg-backup-$(shell date +%Y%m%d-%H%M%S)"
	@$(run_as_root) sh -c 'bk="/root/wg-backup-$(shell date +%Y%m%d-%H%M%S)"; mkdir -p "$$bk"; cp -a /etc/wireguard/*.key /etc/wireguard/*.pub /etc/wireguard/*.conf "$$bk"/ || true'
	@echo "Regenerating server keys and configs (FORCE=1 CONF_FORCE=1)..."
	@for i in 0 1 2 3 4 5 6 7; do \
	  echo " -> make wg$$i"; \
	  $(run_as_root) sh -c 'FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) $(MAKE) wg'"$$i"'' || { echo "ERROR: wg$$i failed"; exit 1; }; \
	done
	@echo "Regenerating client configs (regen-clients IFACE=wgN)..."
	@for i in 0 1 2 3 4 5 6 7; do \
	  echo " -> regen-clients IFACE=wg$$i"; \
	  $(run_as_root) sh -c 'FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) $(MAKE) regen-clients IFACE=wg'"$$i"''; \
	done
	@echo "Ensuring peers and reloading runtime (wg-add-peers)..."
	@$(run_as_root) sh -c 'FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) $(MAKE) wg-add-peers'
	@echo "Restarting interfaces..."
	@for i in 0 1 2 3 4 5 6 7; do \
	  echo " -> restart wg$$i"; \
	  $(run_as_root) $(WG_QUICK) down wg$$i || true; \
	  $(run_as_root) $(WG_QUICK) up wg$$i || echo "WARNING: wg$$i failed to start"; \
	done
	@echo "Final runtime status:" \
	&& $(run_as_root) sh -c '$(WG_BIN) show'
