# mk/20_sysctl.mk

# --- CONFIGURATION & PATHS ---
SYSCTL_SRC := $(REPO_ROOT)/config/sysctl.d/99-homelab-forwarding.conf
SYSCTL_DST := /etc/sysctl.d/99-homelab-forwarding.conf
SYSCTL_BIN := /sbin/sysctl

# Extract IID from constants (e.g., ::4)
NAS_IID_TOKEN := ::$(shell echo "$(NAS_LAN_IP6)" | sed 's/.*:://')

.PHONY: install-homelab-sysctl sysctl-inspect sysctl-preflight set-ipv6-token rotate-ipv6-secrets ensure-accept-ra

# --- OPERATOR-GRADE MACROS ---

define sysctl_preflight_check
{ \
	echo "🔍 Verifying system dependencies..."; \
	for cmd in ip awk sed grep python3 openssl; do \
		if ! command -v $$cmd >/dev/null 2>&1; then \
			echo "❌ ERROR: Required command '$$cmd' not found."; exit 1; \
		fi; \
	done; \
	if [ ! -f "$(SYSCTL_SRC)" ]; then \
		echo "❌ ERROR: Source config $(SYSCTL_SRC) missing."; exit 1; \
	fi; \
	if ! grep -q 'net.ipv6.conf.eth0.accept_ra' "$(SYSCTL_SRC)"; then \
		echo "❌ ERROR: $(SYSCTL_SRC) is missing sysctl config missing net.ipv6.conf.eth0.accept_ra = 2 (IPv6 black-hole guard)."; exit 1; \
	fi; \
}
endef

define inspect_ipv6_identity
{ \
	echo "🔍 Current IPv6 Identity Mapping:"; \
	echo "--------------------------------------------------------------------------------"; \
	ip -6 -oneline addr show scope global | grep -v "tentative" | awk -v target="$(NAS_IID_TOKEN)" ' \
	{ \
		split($$4, a, "/"); addr=a[1]; \
		n=split(addr, groups, ":"); \
		iid=groups[n-3]":"groups[n-2]":"groups[n-1]":"groups[n]; \
		status = (addr ~ target"$$") ? "✅" : "⚠️  MISMATCH"; \
		printf "%-11s | Interface: %-6s | Addr: %s\n", status, $$2, addr; \
	}' | sort -u; \
	echo "--------------------------------------------------------------------------------"; \
	echo "🔍 accept_ra status (must be 2 on eth0 to survive forwarding=1):"; \
	for iface in eth0; do \
		[ -f "/proc/sys/net/ipv6/conf/$$iface/accept_ra" ] || continue; \
		val=$$(cat "/proc/sys/net/ipv6/conf/$$iface/accept_ra"); \
		if [ "$$val" = "2" ]; then \
			echo "✅ $$iface: accept_ra = $$val"; \
		else \
			echo "❌ $$iface: accept_ra = $$val (expected 2 - IPv6 default route will be missing!)"; \
		fi; \
	done; \
	echo "--------------------------------------------------------------------------------"; \
}
endef

define set_ipv6_token
{ \
	echo "📍 Checking IPv6 ULA address convergence ($(NAS_LAN_IP6))..."; \
	for iface in eth0; do \
		if [ -d "/sys/class/net/$$iface" ]; then \
			if ip -6 addr show dev $$iface scope global | grep -q " $(NAS_LAN_IP6)/"; then \
				echo "✅ $$iface: ULA IPv6 address already converged to $(NAS_LAN_IP6)."; \
			else \
				echo "🔄 $$iface: ULA IPv6 not found. Adding $(NAS_LAN_IP6)..."; \
				$(run_as_root) ip -6 addr add $(NAS_LAN_IP6)/64 dev $$iface 2>/dev/null || true; \
				echo "✨ $$iface: IPv6 address set to $(NAS_LAN_IP6)/64."; \
				echo "ℹ️ Any ISP-delegated global IPv6 from router RA is preserved (needed for NAT66)."; \
			fi; \
		fi; \
	done; \
}
endef

define inject_ipv6_secrets
{ \
	echo "🔐 Generating hardware-linked IPv6 secrets..."; \
	pool=$$(openssl rand -hex 32); \
	s1=$$(echo $$pool | cut -c1-32 | sed "s/\(..\)/\1:/g; s/:$$//"); \
	{ \
		printf "\n# --- Homelab IPv6 Stable Secrets ---\n"; \
		[ -d /sys/class/net/eth0 ] && printf "net.ipv6.conf.eth0.stable_secret = %s\n" "$$s1"; \
	} | $(run_as_root) tee -a "$(SYSCTL_DST)" >/dev/null; \
}
endef

# --- TARGETS ---

sysctl-preflight:
	@set -eu; ( $(sysctl_preflight_check) )

sysctl-inspect: sysctl-preflight
	@set -eu; ( $(inspect_ipv6_identity) )

set-ipv6-token: ensure-run-as-root
	@set -eu; ( $(set_ipv6_token) )

# Verify effective accept_ra =2 on eth0 without touching sysctl files.
# Run after install-homelab-sysctl to confirm the kernel absorbed the setting.
ensure-accept-ra:
	@set -eu; \
	val=$$(cat /proc/sys/net/ipv6/conf/eth0/accept_ra 2>/dev/null || echo "missing"); \
	if [ "$$val" != "2" ]; then \
		echo "❌ eth0: net.ipv6.conf.eth0.accept_ra = $$val (expected 2). Run: make install-homelab-sysctl"; \
		exit 1; \
	fi; \
	echo "✅ net.ipv6.conf.eth0.accept_ra = 2 - IPv6 default route will be accepted from router RA."; \

install-homelab-sysctl: ensure-run-as-root sysctl-preflight set-ipv6-token
	@set -eu; \
	echo "🔄 Syncing functional sysctl configuration..."; \
	$(run_as_root) install -o root -g root -m 0644 "$(SYSCTL_SRC)" "$(SYSCTL_DST)"; \
	$(run_as_root) $(SYSCTL_BIN) -p "$(SYSCTL_DST)" >/dev/null; \
	echo "✨ Convergence verified: NAS IPv6 address is $(NAS_LAN_IP6)/64 (RA-independent)"; \

rotate-ipv6-secrets: ensure-run-as-root sysctl-preflight
	@echo "🔄 Scrambling IPv6 identity (RFC 7217)..."
	@set -eu; \
	$(run_as_root) sh -e -c '\
		sed -i "/stable_secret/d; /Homelab/d" "$(SYSCTL_DST)"; \
		pool=$$(openssl rand -hex 32); \
		s1=$$(echo $$pool | cut -c1-32 | sed "s/\(..\)/\1:/g; s/:$$//"); \
		{ \
			printf "\n\n# --- Homelab IPv6 Stable Secrets ---\n"; \
			[ -d /sys/class/net/eth0 ] && printf "net.ipv6.conf.eth0.stable_secret = %s\n" "$$s1"; \
		} >> "$(SYSCTL_DST)"; \
		sleep 5; \
		reboot; \
	'
