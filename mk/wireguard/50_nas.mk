# --------------------------------------------------------------------
# mk/wireguard/50_nas.mk — NAS Control Plane
# --------------------------------------------------------------------

wg-install-nas: $(INSTALL_PATH)/wgctl.sh \
		$(INSTALL_PATH)/wg-readiness-probe.sh \
		| wg-generate
		@echo "📦 [nas   ] Installing WireGuard configurations..."; \
		EXECUTE_DEPLOY=0; \
		if [ -f "$(WG_NAS_DIRTY_STAMP)" ]; then EXECUTE_DEPLOY=1; fi; \
		for iface in $(WG_INTERFACES_NAS); do \
				if ! [ -f "$(WG_OUTPUT_ROUTER)/$$iface.conf" ]; then continue; fi; \
				EXPECTED_GEN=$$(grep -E '^#[[:space:]]*WG_GENERATION:' "$(WG_OUTPUT_ROUTER)/$$iface.conf" | awk '{print $$3}' 2>/dev/null || echo "0"); \
				if [ -x "$(INSTALL_PATH)/wg-readiness-probe.sh" ]; then \
						if ! "$(INSTALL_PATH)/wg-readiness-probe.sh" "$$iface" "$(WG_OUTPUT_ROUTER)/$$iface.conf" "$$EXPECTED_GEN" "$(STAMP_DIR_ROOT)"; then \
								echo "⚠️  Kernel link drift verified on NAS interface $$iface"; \
								EXECUTE_DEPLOY=1; \
						fi; \
				else \
						echo "⚠️  Readiness probe missing — forcing execution pass"; \
						EXECUTE_DEPLOY=1; \
				fi; \
		done; \
		if [ "$$EXECUTE_DEPLOY" -eq 1 ]; then \
				echo "🚀 Executing NAS control plane tunnel provision..."; \
				EC=0; \
				$(WG_ENV) \
				NAS_CONTROL_PLANE=1 \
				$(WG_SUDO) $(INSTALL_PATH)/wgctl.sh nas install-up || EC=$$?; \
				if [ "$$EC" != "0" ] && [ "$$EC" != "3" ]; then exit "$$EC"; fi; \
				$(WG_SUDO) rm -f "$(WG_NAS_DIRTY_STAMP)"; \
		else \
				echo "✨ NAS interfaces match runtime expectations (skipping processing)"; \
		fi

wg-up-nas: wg-install-nas
		@$(WG_SUDO) \
				$(WG_ENV) \
				NAS_CONTROL_PLANE=1 \
				$(INSTALL_PATH)/wgctl.sh nas up

wg-down-nas:
		@$(WG_SUDO) \
				$(WG_ENV) \
				NAS_CONTROL_PLANE=1 \
				$(INSTALL_PATH)/wgctl.sh nas down

wg7-validate:
		@echo "🔍 [wg7] Step 1/5 — checking wg7 interface on NAS..."; \
		$(WG_SUDO) wg show wg7 >/dev/null 2>&1 \
				&& echo "   ✅ wg7 interface present" \
				|| { echo "   ❌ wg7 interface missing — run: make wg-install-nas"; exit 1; }; \
		echo "🔍 [wg7] Step 2/5 — IPv4 connectivity..."; \
		wg7_ip="$$( $(WG_SUDO) wg show wg7 2>/dev/null | awk '/address:/{print $$2}' | cut -d/ -f1 )"; \
		if [ -n "$$wg7_ip" ]; then \
				ping -c2 -W2 "$$wg7_ip" >/dev/null 2>&1 \
						&& echo "   ✅ wg7 IPv4 self-ping OK" \
						|| echo "   ⚠️  wg7 IPv4 self-ping failed"; \
		else \
				echo "   ⚠️  wg7 has no assigned IP address"; \
		fi; \
		echo "🔍 [wg7] Step 3/5 — NAS eth0 global IPv6..."; \
		$(WG_SUDO) ip -6 addr show dev eth0 scope global | grep -q 'inet6' \
				&& echo "   ✅ NAS eth0 has a global IPv6 address" \
				|| echo "   ❌ NAS eth0 has NO global IPv6"; \
		echo "🔍 [wg7] Step 4/5 — nftables NAT66 rule..."; \
		$(WG_SUDO) nft list chain ip6 homelab_nat6 postrouting 2>/dev/null | grep -q 'masquerade' \
				&& echo "   ✅ homelab_nat6 masquerade rule active" \
				|| echo "   ❌ homelab_nat6 masquerade not loaded"; \
		echo "🔍 [wg7] Step 5/5 — outbound IPv6 reachability..."; \
		curl -6 -s --max-time 5 https://ifconfig.io >