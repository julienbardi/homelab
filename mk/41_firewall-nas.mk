# --------------------------------------------------------------------
# mk/41_firewall-nas.mk — NAS firewall invariants
# --------------------------------------------------------------------
# CONTRACT:
# - Explicitly allow trusted subnets to access NAS services
# - Default-deny posture preserved
# - Idempotent and safe to re-run
# --------------------------------------------------------------------

include $(STAMP_DIR_ROOT)/wg-subnets.mk

# Derived from authoritative wg-interfaces.tsv via wg-plan-subnets.sh
ROUTER_WG_SUBNET   := $(WG_ROUTER_SUBNET_V4)
ROUTER_WG_SUBNET6  := $(WG_ROUTER_SUBNET_V6)

IPTABLES  := /usr/sbin/iptables
IP6TABLES := /usr/sbin/ip6tables

$(if $(wildcard $(IPTABLES)),,$(error iptables not found at $(IPTABLES)))
$(if $(wildcard $(IP6TABLES)),,$(error ip6tables not found at $(IP6TABLES)))

.PHONY: firewall-nas

# IPv6 rules only if router WG IPv6 subnet exists
ifneq ($(strip $(ROUTER_WG_SUBNET6)),)

firewall-nas: $(STAMP_DIR_ROOT)/wg-subnets.mk
	@echo "🔓 Allowing router-terminated WireGuard clients to access NAS"

	@if ! $(run_as_root) $(IPTABLES) -C INPUT -s $(ROUTER_WG_SUBNET)   -d $(NAS_LAN_IP) -p tcp -j ACCEPT 2>/dev/null; then \
		  $(run_as_root) $(IPTABLES) -I INPUT -s $(ROUTER_WG_SUBNET)   -d $(NAS_LAN_IP) -p tcp -j ACCEPT; \
	fi

	@if ! $(run_as_root) $(IPTABLES) -C INPUT -s $(ROUTER_WG_SUBNET)   -d $(NAS_LAN_IP) -p udp -j ACCEPT 2>/dev/null; then \
		  $(run_as_root) $(IPTABLES) -I INPUT -s $(ROUTER_WG_SUBNET)   -d $(NAS_LAN_IP) -p udp -j ACCEPT; \
	fi

	@if ! $(run_as_root) $(IP6TABLES) -C INPUT -s $(ROUTER_WG_SUBNET6) -d $(NAS_LAN_IP6) -p tcp -j ACCEPT 2>/dev/null; then \
		  $(run_as_root) $(IP6TABLES) -I INPUT -s $(ROUTER_WG_SUBNET6) -d $(NAS_LAN_IP6) -p tcp -j ACCEPT; \
	fi

	@if ! $(run_as_root) $(IP6TABLES) -C INPUT -s $(ROUTER_WG_SUBNET6) -d $(NAS_LAN_IP6) -p udp -j ACCEPT 2>/dev/null; then \
		  $(run_as_root) $(IP6TABLES) -I INPUT -s $(ROUTER_WG_SUBNET6) -d $(NAS_LAN_IP6) -p udp -j ACCEPT; \
	fi

else

# Skip IPv4 rules if WG IPv4 subnet is empty
ifeq ($(strip $(ROUTER_WG_SUBNET)),)
firewall-nas:
	@echo "⏭️ Skipping NAS IPv4 firewall rules: ROUTER_WG_SUBNET is empty"
else

firewall-nas: $(STAMP_DIR_ROOT)/wg-subnets.mk
	@echo "🔓 Allowing router-terminated WireGuard clients to access NAS (IPv4 only)"

	@if ! $(run_as_root) $(IPTABLES) -C INPUT -s $(ROUTER_WG_SUBNET)   -d $(NAS_LAN_IP) -p tcp -j ACCEPT 2>/dev/null; then \
		  $(run_as_root) $(IPTABLES) -I INPUT -s $(ROUTER_WG_SUBNET)   -d $(NAS_LAN_IP) -p tcp -j ACCEPT; \
	fi

	@if ! $(run_as_root) $(IPTABLES) -C INPUT -s $(ROUTER_WG_SUBNET)   -d $(NAS_LAN_IP) -p udp -j ACCEPT 2>/dev/null; then \
		  $(run_as_root) $(IPTABLES) -I INPUT -s $(ROUTER_WG_SUBNET)   -d $(NAS_LAN_IP) -p udp -j ACCEPT; \
	fi

endif  # ROUTER_WG_SUBNET empty guard
endif  # IPv6/IPv4 branch


.PHONY: install-nft-apply nft-apply nft-confirm nft-install nft-status nft-install nft-verify nft-install-rollback
.NOTPARALLEL: nft-confirm nft-apply

install-nft-apply:
	@$(run_as_root) install -o $(ROOT_UID) -g $(ROOT_GID) -m 0755 $(REPO_ROOT)/scripts/homelab-nft-apply.sh $(INSTALL_PATH)/homelab-nft-apply.sh

nft-sync:
	@status=0; \
	$(run_as_root) env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(INSTALL_FILE_IF_CHANGED) \
			"" "" "$(REPO_ROOT)/scripts/homelab.nft" \
			"" "" "$(HOMELAB_NFT_RULESET)" \
			"$(ROOT_UID)" "$(ROOT_GID)" "0644" \
		|| status=$$?; \
	case "$$status" in ''|*[!0-9]*) status=1 ;; esac; \
	if [ $$status -ne 0 ] && [ $$status -ne $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		echo "❌ Fatal error (exit $$status) installing $(HOMELAB_NFT_RULESET)" >&2; \
		exit $$status; \
	fi

nft-apply: install-nft-apply nft-sync
	@$(run_as_root) sh -c '\
		echo "🔧 Applying nftables ruleset"; \
		$(INSTALL_PATH)/homelab-nft-apply.sh >/dev/null 2>&1 || true; \
		sha256sum "$(HOMELAB_NFT_RULESET)" | awk "{print \$$1}" > "$(HOMELAB_NFT_HASH_FILE)"; \
		echo "📋 Recorded nftables ruleset hash"; \
	'

nft-confirm:
	@status=0; \
	$(run_as_root) sh -c '$(INSTALL_PATH)/homelab-nft-confirm.sh' || status=$$?; \
	case "$$status" in ''|*[!0-9]*) status=1 ;; esac; \
	if [ $$status -ne 0 ]; then \
		echo "❌ homelab-nft-confirm.sh failed (exit $$status)"; \
		exit $$status; \
	fi

nft-install: install-nft-apply
	@$(run_as_root) sh -c '\
		echo "🛡️ Installing homelab nftables firewall"; \
		install -o $(ROOT_UID) -g $(ROOT_GID) -m 0755 $(REPO_ROOT)/scripts/homelab-nft-confirm.sh $(INSTALL_PATH)/homelab-nft-confirm.sh; \
		install -o $(ROOT_UID) -g $(ROOT_GID) -m 0755 $(REPO_ROOT)/scripts/homelab-nft-rollback.sh $(INSTALL_PATH)/homelab-nft-rollback.sh; \
		install -o $(ROOT_UID) -g $(ROOT_GID) -m 0644 $(REPO_ROOT)/config/systemd/homelab-nft.service /etc/systemd/system/homelab-nft.service; \
		install -o $(ROOT_UID) -g $(ROOT_GID) -m 0644 $(REPO_ROOT)/config/systemd/homelab-nft-rollback.service /etc/systemd/system/homelab-nft-rollback.service; \
		install -o $(ROOT_UID) -g $(ROOT_GID) -m 0644 $(REPO_ROOT)/config/systemd/homelab-nft-rollback.timer /etc/systemd/system/homelab-nft-rollback.timer; \
		systemctl daemon-reload >/dev/null 2>&1; \
		systemctl enable homelab-nft.service homelab-nft-rollback.timer >/dev/null 2>&1 || true; \
		echo "✅ Firewall units installed (not yet applied)"; \
	'

nft-status:
	@$(run_as_root) nft list table inet homelab_filter

nft-install-rollback:
	@$(run_as_root) sh -c '\
		echo "⏪ Installing homelab nft rollback units"; \
		install -o $(ROOT_UID) -g $(ROOT_GID) -m 0644 $(REPO_ROOT)/config/systemd/homelab-nft-rollback.service /etc/systemd/system/homelab-nft-rollback.service; \
		install -o $(ROOT_UID) -g $(ROOT_GID) -m 0644 $(REPO_ROOT)/config/systemd/homelab-nft-rollback.timer /etc/systemd/system/homelab-nft-rollback.timer; \
		systemctl daemon-reload >/dev/null 2>&1; \
		systemctl enable homelab-nft-rollback.timer >/dev/null 2>&1 || true; \
		echo "✅ nft rollback units installed"; \
	'
