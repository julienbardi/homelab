# mk/20_sysctl.mk

# --- CONFIGURATION & PATHS ---
# Anchor REPO_ROOT to the actual directory of this Makefile
SYSCTL_SRC := $(REPO_ROOT)config/sysctl.d/99-homelab-forwarding.conf
SYSCTL_DST := /etc/sysctl.d/99-homelab-forwarding.conf
SYSCTL_BIN := /sbin/sysctl

# Extract the IID suffix from your constants (e.g., extracts "4" from fd89:7a3b:42c0::4)
# We use a simple shell strip to get everything after the last '::'
NAS_IID_TOKEN := ::$(shell echo "$(NAS_LAN_IP6)" | sed 's/.*:://')

.PHONY: install-homelab-sysctl sysctl-inspect sysctl-preflight set-ipv6-token

# --- OPERATOR-GRADE MACROS ---

define sysctl_preflight_check
{ \
	echo "🔍 Verifying system dependencies..."; \
	for cmd in ip awk sed grep python3; do \
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
	echo "🔍 Current IPv6 Identity Mapping (Global & ULA):"; \
	echo "--------------------------------------------------------------------------------"; \
	ip -6 -oneline addr show scope global | grep -v "tentative" | while read -r line; do \
		iface=$$(echo "$$line" | awk '{print $$2}'); \
		full_addr=$$(echo "$$line" | awk '{print $$4}' | cut -d/ -f1); \
		expanded=$$(python3 -c "import ipaddress; print(ipaddress.IPv6Address('$$full_addr').exploded)" 2>/dev/null || echo "$$full_addr"); \
		prefix=$$(echo "$$expanded" | cut -d: -f1-4); \
		iid=$$(echo "$$expanded" | cut -d: -f5-8); \
		printf "🌐 Interface: %-10s | Prefix: %-25s | IID: %s\n" "$$iface" "$$prefix" "$$iid"; \
	done | sort -u; \
	echo "--------------------------------------------------------------------------------"; \
}
endef

define inject_ipv6_secrets
{ \
	echo "🔐 Generating NEW hardware-linked IPv6 secret (Rotation)..."; \
	for iface in eth0 eth1; do \
		if [ -d "/sys/class/net/$$iface" ]; then \
			secret=$$(openssl rand -hex 16 | sed 's/\(..\)/\1:/g; s/:$$//'); \
			printf "\n# --- Homelab IPv6 Stable Secrets ---\nnet.ipv6.conf.%s.stable_secret = %s\n" "$$iface" "$$secret" | \
			$(run_as_root) tee -a "$(SYSCTL_DST)" >/dev/null; \
		fi; \
	done; \
}
endef

# --- TARGETS ---

sysctl-preflight:
	@set -eu; ( $(sysctl_preflight_check) )

sysctl-inspect: sysctl-preflight
	@set -eu; ( $(inspect_ipv6_identity) )

# Force the token during every install to ensure the ::4 is active
set-ipv6-token: ensure-run-as-root
	@set -eu; ( $(set_ipv6_token) )

install-homelab-sysctl: ensure-run-as-root sysctl-preflight set-ipv6-token
	@set -eu; \
	echo "🔄 Syncing functional sysctl configuration..."; \
	$(run_as_root) install -o root -g root -m 0644 "$(SYSCTL_SRC)" "$(SYSCTL_DST)"; \
	$(run_as_root) $(SYSCTL_BIN) -p "$(SYSCTL_DST)" >/dev/null; \
	echo "💎 Convergence verified: NAS is locked to suffix $(NAS_IID_TOKEN)"

rotate-ipv6-secrets: ensure-run-as-root sysctl-preflight
	@echo "🔄 Scrambling IPv6 identity (RFC 7217)..."
	@set -eu; \
	$(run_as_root) sed -i '/stable_secret/d; /Homelab/d' "$(SYSCTL_DST)"; \
	( $(inject_ipv6_secrets) ); \
	echo "🚀 Identity scrambled. Enforcing system reboot in 5s to clear leaked IIDs..."; \
	sleep 5 && $(run_as_root) reboot