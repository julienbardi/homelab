STATUS: SPECIFICATION — NOT EXECUTABLE
# Step 6 — WireGuard forwarding firewall
# -------------------------------------
# CONTRACT:
# - Declarative generation from interface intent
# - No legacy cleanup
# - Rule order is authoritative
# - Default deny
# -------------------------------------
# INPUTS:
# - WG_INTERFACES (resolved list)
# - Per-interface flags (Make variables):
#     * <wg>_reach_lan_v4 / <wg>_reach_lan_v6
#     * <wg>_reach_wan_v4 / <wg>_reach_wan_v6
#     * <wg>_dns_policy
#     * <wg>_dns_families
#   Example:
#     wgs1_reach_lan_v4 := yes
#     wgs1_reach_wan_v4 := no
# - Router interfaces:
#     * WAN_IF (e.g. eth0)
#     * LAN_IF (e.g. br0)
# - Internal DNS:
#     * DNS4 = 10.89.12.4
#     * DNS6 = fd89:7a3b:42c0::4
# OUTPUTS:
# - IPv4 chain: WG_FWD4
# - IPv6 chain: WG_FWD6
# - Scoped FORWARD jumps:
#     FORWARD -i wg+ → WG_FWD*
#     FORWARD -o wg+ → WG_FWD*
# - Default policy: DROP (inside WG_FWD*)  [added later]
# -------------------------------------

# Router connection (single source of truth)
ROUTER_HOST      ?= julie@10.89.12.1
ROUTER_USER      := $(word 1,$(subst @, ,$(ROUTER_HOST)))
ROUTER_ADDR      := $(word 2,$(subst @, ,$(ROUTER_HOST)))
ROUTER_SSH_PORT  ?= 2222
ROUTER_SCRIPTS   ?= /jffs/scripts

# Render vs apply
# - STEP6_APPLY=yes: execute on router via SSH
# - STEP6_APPLY=no : print commands only (audit)
STEP6_APPLY ?= yes

define maybe_run
	@if [ "$(STEP6_APPLY)" = "yes" ]; then \
		printf '%s\n' "$1" | ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) sh -s; \
	else \
		printf '%s\n' "$1"; \
	fi
endef

# Access per-interface intent flags as Make variables:
#   $(call wg_flag,wgs1,reach_lan_v4) -> expands to value of wgs1_reach_lan_v4
wg_flag = $(strip $($(1)_$(2)))

ifeq ($(ROLE),router)
# Step 6 applies
else
$(error Step 6 firewall must not run for ROLE=$(ROLE))
endif

$(if $(WG_INTERFACES),,$(error WG_INTERFACES is empty/undefined))
$(if $(WAN_IF),,$(error WAN_IF is empty/undefined))
$(if $(LAN_IF),,$(error LAN_IF is empty/undefined))

IPTABLES  := /usr/sbin/iptables
IP6TABLES := /usr/sbin/ip6tables

$(if $(wildcard $(IPTABLES)),,$(error iptables not found at $(IPTABLES)))
$(if $(wildcard $(IP6TABLES)),,$(error ip6tables not found at $(IP6TABLES)))

.PHONY: step6-firewall

step6-firewall:
	@echo "→ Step 6 WireGuard firewall (apply=$(STEP6_APPLY))"

	@echo "→ Ensuring WG_FWD4 chain"
	@$(call maybe_run,$(IPTABLES) -N WG_FWD4 2>/dev/null || true)
	@$(call maybe_run,$(IPTABLES) -F WG_FWD4)

	@echo "→ Ensuring WG_FWD6 chain"
	@$(call maybe_run,$(IP6TABLES) -N WG_FWD6 2>/dev/null || true)
	@$(call maybe_run,$(IP6TABLES) -F WG_FWD6)

	@echo "→ Enforcing scoped FORWARD hooks (IPv4)"
	@while $(IPTABLES) -C FORWARD -j WG_FWD4 2>/dev/null; do \
		$(call maybe_run,$(IPTABLES) -D FORWARD -j WG_FWD4); \
	done
	@while $(IPTABLES) -C FORWARD -i wg+ -j WG_FWD4 2>/dev/null; do \
		$(call maybe_run,$(IPTABLES) -D FORWARD -i wg+ -j WG_FWD4); \
	done
	@while $(IPTABLES) -C FORWARD -o wg+ -j WG_FWD4 2>/dev/null; do \
		$(call maybe_run,$(IPTABLES) -D FORWARD -o wg+ -j WG_FWD4); \
	done
	@$(call maybe_run,$(IPTABLES) -I FORWARD 1 -i wg+ -j WG_FWD4)
	@$(call maybe_run,$(IPTABLES) -I FORWARD 2 -o wg+ -j WG_FWD4)

	@echo "→ Enforcing scoped FORWARD hooks (IPv6)"
	@while $(IP6TABLES) -C FORWARD -j WG_FWD6 2>/dev/null; do \
		$(call maybe_run,$(IP6TABLES) -D FORWARD -j WG_FWD6); \
	done
	@while $(IP6TABLES) -C FORWARD -i wg+ -j WG_FWD6 2>/dev/null; do \
		$(call maybe_run,$(IP6TABLES) -D FORWARD -i wg+ -j WG_FWD6); \
	done
	@while $(IP6TABLES) -C FORWARD -o wg+ -j WG_FWD6 2>/dev/null; do \
		$(call maybe_run,$(IP6TABLES) -D FORWARD -o wg+ -j WG_FWD6); \
	done
	@$(call maybe_run,$(IP6TABLES) -I FORWARD 1 -i wg+ -j WG_FWD6)
	@$(call maybe_run,$(IP6TABLES) -I FORWARD 2 -o wg+ -j WG_FWD6)

	@echo "→ Allowing ESTABLISHED,RELATED (IPv4)"
	@$(call maybe_run,$(IPTABLES) -A WG_FWD4 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT)

	@echo "→ Allowing ESTABLISHED,RELATED (IPv6)"
	@$(call maybe_run,$(IP6TABLES) -A WG_FWD6 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT)

	@echo "→ Emitting per-interface allow rules"
	@for WG_IF in $(WG_INTERFACES); do \
		echo "   → $$WG_IF"; \
		if [ "$(call wg_flag,$$WG_IF,reach_lan_v4)" = "yes" ]; then \
			$(call maybe_run,$(IPTABLES) -A WG_FWD4 -i $$WG_IF -o $(LAN_IF) -j ACCEPT); \
		fi; \
		if [ "$(call wg_flag,$$WG_IF,reach_wan_v4)" = "yes" ]; then \
			$(call maybe_run,$(IPTABLES) -A WG_FWD4 -i $$WG_IF -o $(WAN_IF) -j ACCEPT); \
		fi; \
		if [ "$(call wg_flag,$$WG_IF,reach_lan_v6)" = "yes" ]; then \
			$(call maybe_run,$(IP6TABLES) -A WG_FWD6 -i $$WG_IF -o $(LAN_IF) -j ACCEPT); \
		fi; \
		if [ "$(call wg_flag,$$WG_IF,reach_wan_v6)" = "yes" ]; then \
			$(call maybe_run,$(IP6TABLES) -A WG_FWD6 -i $$WG_IF -o $(WAN_IF) -j ACCEPT); \
		fi; \
	done
