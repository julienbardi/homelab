# mk/20_sysctl.mk

# --- CONFIGURATION & PATHS ---
SYSCTL_SRC := $(REPO_ROOT)config/sysctl.d/99-homelab-forwarding.conf
SYSCTL_DST := /etc/sysctl.d/99-homelab-forwarding.conf
SYSCTL_BIN := /sbin/sysctl

# Extract IID from constants (e.g., ::4)
NAS_IID_TOKEN := ::$(shell echo "$(NAS_LAN_IP6)" | sed 's/.*:://')

.PHONY: install-homelab-sysctl sysctl-inspect sysctl-preflight set-ipv6-token rotate-ipv6-secrets

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
}
endef

define set_ipv6_token
{ \
	echo "📍 Locking IPv6 Token to $(NAS_IID_TOKEN)..."; \
	for iface in eth0 eth1; do \
		if [ -d "/sys/class/net/$$iface" ]; then \
			$(run_as_root) ip token set $(NAS_IID_TOKEN) dev $$iface; \
			$(run_as_root) ip link set dev $$iface down; \
			$(run_as_root) ip link set dev $$iface up; \
			echo "✅ Token $(NAS_IID_TOKEN) applied to $$iface"; \
		fi; \
	done; \
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
}
endef

define set_ipv6_token
{ \
	echo "📍 Checking IPv6 Token convergence..."; \
	for iface in eth0 eth1; do \
		[ ! -d "/sys/class/net/$$iface" ] && continue; \
		current=$$(ip token list dev $$iface | awk '{print $$1}'); \
		[ "$$current" = "$(NAS_IID_TOKEN)" ] && { echo "✅ $$iface: Matches."; continue; }; \
		echo "🔄 $$iface: Updating to $(NAS_IID_TOKEN)..."; \
		$(run_as_root) ip token set $(NAS_IID_TOKEN) dev $$iface; \
		$(run_as_root) ip link set dev $$iface down; \
		$(run_as_root) ip link set dev $$iface up; \
	done; \
}
endef

define set_ipv6_token
{ \
	echo "📍 Checking IPv6 Token convergence ($(NAS_IID_TOKEN))..."; \
	for iface in eth0 eth1; do \
		if [ -d "/sys/class/net/$$iface" ]; then \
			current_token=$$(ip token list dev $$iface | awk '{print $$1}'); \
			if [ "$$current_token" = "$(NAS_IID_TOKEN)" ]; then \
				echo "✅ $$iface: Token already matches. Skipping cycle."; \
			else \
				echo "🔄 $$iface: Token mismatch. Applying $(NAS_IID_TOKEN)..."; \
				$(run_as_root) ip token set $(NAS_IID_TOKEN) dev $$iface; \
				$(run_as_root) ip link set dev $$iface down; \
				$(run_as_root) ip link set dev $$iface up; \
				echo "✨ $$iface: Token applied and link cycled."; \
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
	s2=$$(echo $$pool | cut -c33-64 | sed "s/\(..\)/\1:/g; s/:$$//"); \
	{ \
		printf "\n# --- Homelab IPv6 Stable Secrets ---\n"; \
		[ -d /sys/class/net/eth0 ] && printf "net.ipv6.conf.eth0.stable_secret = %s\n" "$$s1"; \
		[ -d /sys/class/net/eth1 ] && printf "net.ipv6.conf.eth1.stable_secret = %s\n" "$$s2"; \
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

install-homelab-sysctl: ensure-run-as-root sysctl-preflight set-ipv6-token
	@set -eu; \
	echo "🔄 Syncing functional sysctl configuration..."; \
	$(run_as_root) install -o root -g root -m 0644 "$(SYSCTL_SRC)" "$(SYSCTL_DST)"; \
	$(run_as_root) $(SYSCTL_BIN) -p "$(SYSCTL_DST)" >/dev/null; \
	echo "✨ Convergence verified: NAS is locked to suffix $(NAS_IID_TOKEN)"

rotate-ipv6-secrets: ensure-run-as-root sysctl-preflight
	@echo "🔄 Scrambling IPv6 identity (RFC 7217)..."
	@set -eu; \
	$(run_as_root) sed -i '/stable_secret/d; /Homelab/d' "$(SYSCTL_DST)"; \
	( $(inject_ipv6_secrets) ); \
	echo "🚀 Identity scrambled. Enforcing system reboot in 5s to clear leaked IIDs..."; \
	sleep 5 && $(run_as_root) reboot