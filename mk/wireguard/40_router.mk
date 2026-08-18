# --------------------------------------------------------------------
# mk/wireguard/40_router.mk — Router Control Plane
# --------------------------------------------------------------------

router-ensure-wg-module: router-install-scripts
		@if [ -z "$(ROUTER_WG_DIR)" ]; then echo "ERROR: ROUTER_WG_DIR undefined"; exit 1; fi; \
		echo "🛡️ [router] Ensuring WireGuard kernel module on $(ROUTER_ADDR):$(ROUTER_SSH_PORT)..."; \
		ssh "$(SSH_HOST_ROUTER)" 'modprobe wireguard 2>/dev/null || true'

# VERSION: 2026.08.17-clean-router-keys
router-bootstrap-wg-keys:
	@ssh "$(SSH_HOST_ROUTER)" ' \
		set -eu; \
		priv="$$(nvram get wgs1_priv 2>/dev/null || true)"; \
		pub="$$(nvram get wgs1_pub 2>/dev/null || true)"; \
		if [ -n "$$priv" ] && [ -n "$$pub" ]; then \
			echo "🔒 Existing WireGuard identity found in NVRAM (wgs1)."; \
			exit 0; \
		fi; \
		echo "🔐 Generating new WireGuard identity for wgs1 in NVRAM..."; \
		wgs1_priv="$$(wg genkey)"; \
		wgs1_pub="$$(printf "%s" "$$wgs1_priv" | wg pubkey)"; \
		nvram set wgs1_priv="$$wgs1_priv"; \
		nvram set wgs1_pub="$$wgs1_pub"; \
		nvram commit; \
		unset wgs1_priv wgs1_pub; \
		echo "✅ Router WireGuard identity stored in NVRAM (wgs1_priv / wgs1_pub)."; \
	'

router-firewall: | wg-generate
	@echo "🛡️ [router] Installing firewall for WireGuard..."; \
	$(call TMPFILE_BLOCK,"$(TMP_ROUTER_WG_FIREWALL)", \
		umask 022; \
		$(WG_SUDO) cat "$(WG_FIREWALL)" > "$(TMP_ROUTER_WG_FIREWALL)"; \
		FEC=0; \
		SSH_CONTROL_PATH="$(SSH_SOCK_FILE_ROUTER)" \
		$(INSTALL_FILE_IF_CHANGED) "-q" \
			"" "" "$(TMP_ROUTER_WG_FIREWALL)" \
			$(ROUTER_HOST) $(ROUTER_SSH_PORT) "$(ROUTER_SCRIPTS)/wg-firewall.sh" \
			"0" "0" "0755" || FEC=$$?; \
		if [ "$$FEC" != "0" ] && [ "$$FEC" != "3" ]; then exit "$$FEC"; fi; \
		if [ "$$FEC" = "0" ]; then \
			ssh "$(SSH_HOST_ROUTER)" "$(ROUTER_SCRIPTS)/wg-firewall.sh" || true; \
		fi \
	)

router-ensure-wg-dir:
	@ssh -i "$(ROUTER_IDENTITY)" -p "$(ROUTER_SSH_PORT)" "$(ROUTER_HOST)" "mkdir -p $(ROUTER_WG_DIR)"

# VERSION: 2026.08.17-router-mk-production
wg-install-router: router-ensure-wg-module \
		router-ensure-wg-dir \
		$(INSTALL_PATH)/wgctl.sh \
		$(INSTALL_PATH)/wg-readiness-probe.sh \
		router-firewall \
		wg-generate
	@echo "📦 Checking and deploying WireGuard configuration files to router..."
	@bash -eu -o pipefail -c '\
		EXECUTE_DEPLOY=0; \
		if ! ssh "$(SSH_HOST_ROUTER)" "test -f $(ROUTER_WG_DIR)/wgs1.conf"; then \
				EXECUTE_DEPLOY=1; \
		fi; \
		STAGE_DIR="$$(mktemp -d)"; \
		trap "rm -rf '\''$$STAGE_DIR'\''" EXIT; \
		sudo sh -c "cp $(WG_OUTPUT_ROUTER)/*.conf '\''$$STAGE_DIR'\''" 2>/dev/null || { \
			echo "❌ ERROR: Failed to copy .conf files from root-owned directory $(WG_OUTPUT_ROUTER)."; \
			exit 1; \
		}; \
		sudo chown -R "$$USER" "$$STAGE_DIR"; \
		sudo chmod -R u+r "$$STAGE_DIR"; \
		for iface in $(WG_INTERFACES_ROUTER); do \
				if [ ! -f "$$STAGE_DIR/$$iface.conf" ]; then continue; fi; \
				EXPECTED_GEN=$$(grep -E "^#[[:space:]]*WG_GENERATION:" "$$STAGE_DIR/$$iface.conf" | awk "{print \$$3}" 2>/dev/null || echo "0"); \
				if [ -x "$(INSTALL_PATH)/wg-readiness-probe.sh" ]; then \
						if ! ROUTER_HOST="$(ROUTER_HOST)" ROUTER_SSH_PORT="$(ROUTER_SSH_PORT)" ROUTER_IDENTITY="$(ROUTER_IDENTITY)" "$(INSTALL_PATH)/wg-readiness-probe.sh" "$$iface" "$$STAGE_DIR/$$iface.conf" "$$EXPECTED_GEN" "$(STAMP_DIR_ROOT)" "router"; then \
								EXECUTE_DEPLOY=1; \
						fi; \
				else \
						EXECUTE_DEPLOY=1; \
				fi; \
		done; \
		if [ "$$EXECUTE_DEPLOY" -eq 1 ]; then \
				echo "📦 Deploying WireGuard configuration files to router..."; \
				for conf in "$$STAGE_DIR"/*.conf; do \
					[ -e "$$conf" ] || continue; \
					basename_conf=$$(basename "$$conf"); \
					ssh -i "$(ROUTER_IDENTITY)" -p "$(ROUTER_SSH_PORT)" \
						-o ControlPath="$(SSH_SOCK_FILE_ROUTER)" \
						-o ControlMaster=auto \
						"$(SSH_HOST_ROUTER)" "cat > $(ROUTER_WG_DIR)/$$basename_conf && chmod 0600 $(ROUTER_WG_DIR)/$$basename_conf" \
						< "$$conf" \
						|| { echo "❌ SSH stream deployment failed for $$basename_conf"; exit 1; }; \
				done; \
				EC=0; \
				SSH_CONTROL_PATH="$(SSH_SOCK_FILE_ROUTER)" \
				$(WG_ENV) \
				ROUTER_CONTROL_PLANE=1 \
				$(INSTALL_PATH)/wgctl.sh router install-up || EC=$$?; \
				if [ "$$EC" != "0" ] && [ "$$EC" != "3" ]; then exit "$$EC"; fi; \
				$(WG_SUDO) rm -f "$(WG_ROUTER_DIRTY_STAMP)"; \
		else \
				echo "✨ Router interfaces match runtime expectations (skipping processing)"; \
		fi \
	'

wg-up-router: wg-install-router
		@SSH_CONTROL_PATH="$(SSH_SOCK_FILE_ROUTER)" \
		$(WG_ENV) \
		ROUTER_CONTROL_PLANE=1 \
		$(INSTALL_PATH)/wgctl.sh router up

wg-down-router:
		@SSH_CONTROL_PATH="$(SSH_SOCK_FILE_ROUTER)" \
				$(WG_ENV) \
				ROUTER_CONTROL_PLANE=1 \
				$(INSTALL_PATH)/wgctl.sh router down

router-wg-health-strict:
		@echo "🔍 Strict WireGuard health check on router"; \
		ssh "$(SSH_HOST_ROUTER)" 'set -e; \
				if ! wg show wgs1 >/dev/null 2>&1; then \
						echo "❌ WireGuard interface wgs1 missing or down"; \
						exit 1; \
				fi; \
				echo "🟢 WireGuard interface wgs1 present"; \
		'

router-wg-audit:
		@echo "🔍 Auditing WireGuard configuration on router"; \
		ssh "$(SSH_HOST_ROUTER)" 'set -e; \
				echo "📝 WireGuard interfaces:"; \
				wg show; \
				echo "📝 Routing table:"; \
				ip route show table all | grep -E "wgs1|wg"; \
		'

wg-router-ipv6-probe:
		@echo "🔍 Probing router IPv6 stack..."; \
		ssh "$(SSH_HOST_ROUTER)" ' \
				echo "🛡️ NAT66 (ip6tables nat) — expected FAIL on Merlin"; \
				ip6tables -t nat -L 2>&1 || echo "  ⚠️  NAT66 not available — expected"; \
				echo ""; \
				echo "🌐 Router Global IPv6 Addresses"; \
				ip -6 addr show scope global 2>/dev/null || echo "  ❌ No global IPv6"; \
				echo ""; \
				echo "🔌 wgs1 IPv6 Addresses"; \
				ip -6 addr show dev wgs1 2>/dev/null || echo "  ⚠️  wgs1 not up"; \
				echo ""; \
				echo "🔁 IPv6 Forwarding State"; \
				if [ -f /proc/sys/net/ipv6/conf/all/forwarding ]; then \
						printf "  forwarding: %s\n" "$$(cat /proc/sys/net/ipv6/conf/all/forwarding)"; \
				else \
						echo "  ⚠️ BusyBox build does not expose IPv6 forwarding"; \
				fi; \
				echo ""; \
				echo "⚙️ Merlin IPv6 Service Mode (NVRAM)"; \
				printf "  ipv6_service: %s\n" "$$(nvram get ipv6_service 2>/dev/null)"; \
		'; \
		echo ""; \
		echo "📡 NAS $(NAS_LAN_IFACE) Global IPv6"; \
		$(WG_SUDO) ip -6 addr show dev $(NAS_LAN_IFACE) scope global 2>/dev/null \
				&& echo "  🟢 NAS receiving RA/PD correctly" \
				|| echo "  ❌ NAS has no global IPv6"
