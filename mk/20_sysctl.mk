# mk/20_sysctl.mk
.PHONY: install-homelab-sysctl rotate-ipv6-secrets sysctl-inspect sysctl-preflight

# --- CONFIGURATION & PATHS ---
REPO_ROOT ?= ./
SYSCTL_SRC := config/sysctl.d/99-homelab-forwarding.conf
SYSCTL_DST := /etc/sysctl.d/99-homelab-forwarding.conf
SYSCTL_BIN := /sbin/sysctl

# --- OPERATOR-GRADE MACROS ---

define sysctl_preflight_check
{ \
	echo "🔍 Verifying system dependencies..."; \
	for cmd in openssl ip awk sed grep; do \
		if ! command -v $$cmd >/dev/null 2>&1; then \
			echo "❌ ERROR: Required command '$$cmd' not found."; exit 1; \
		fi; \
	done; \
	if [ ! -f "$(SYSCTL_SRC)" ]; then \
		echo "❌ ERROR: Source config $(SYSCTL_SRC) missing."; exit 1; \
	fi; \
}
endef

define inspect_ipv6_identity
{ \
	echo "🔍 Current IPv6 Identity Mapping (Global & ULA):"; \
	echo "--------------------------------------------------------"; \
	# Filter for global scope, excluding tentative/deprecated/dynamic privacy addresses \
	ip -6 addr show | grep "scope global" | grep -v "tentative" | awk '{print $$2, $$NF}' | while read addr iface; do \
		prefix=$$(echo $$addr | cut -d':' -f1-4); \
		iid=$$(echo $$addr | cut -d':' -f5-8 | cut -d'/' -f1); \
		printf "🌐 Interface: %-6s | Prefix: %-22s | IID: %s\n" "$$iface" "$$prefix" "$$iid"; \
	done; \
	echo "--------------------------------------------------------"; \
}
endef

define apply_sysctl_file
{ \
	echo "🔄 Syncing functional configuration..."; \
	$(run_as_root) install -o root -g root -m 0644 "$(SYSCTL_SRC)" "$(SYSCTL_DST)"; \
	$(run_as_root) $(SYSCTL_BIN) -p "$(SYSCTL_DST)" >/dev/null; \
}
endef

define inject_ipv6_secrets
{ \
	echo "🔐 Generating hardware-linked IPv6 identity..."; \
	for iface in eth0 eth1; do \
		if [ -d "/sys/class/net/$$iface" ]; then \
			secret=$$(openssl rand -hex 16 | sed 's/\(..\)/\1:/g; s/:$$//'); \
			printf "\n# --- Homelab IPv6 Stable Secrets ---\n# To rotate: make rotate-ipv6-secrets\nnet.ipv6.conf.%s.stable_secret = %s\n" "$$iface" "$$secret" | \
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

install-homelab-sysctl: ensure-run-as-root sysctl-preflight
	@set -eu; \
	changed=0; secret_injected=0; reboot_required=0; \
	if [ ! -f "$(SYSCTL_DST)" ]; then \
		changed=1; \
	else \
		tmp_src=$$(mktemp); tmp_dst=$$(mktemp); \
		sed '/^[[:space:]]*#/d; /^[[:space:]]*$$/d' "$(SYSCTL_SRC)" > "$$tmp_src"; \
		$(run_as_root) sed '/stable_secret/d; /Homelab/d; /rotate/d; /^[[:space:]]*#/d; /^[[:space:]]*$$/d' "$(SYSCTL_DST)" > "$$tmp_dst"; \
		if ! diff -qwb "$$tmp_src" "$$tmp_dst" >/dev/null 2>&1; then changed=1; fi; \
		rm -f "$$tmp_src" "$$tmp_dst"; \
	fi; \
	if [ "$$changed" -eq 1 ]; then ( $(apply_sysctl_file) ); fi; \
	if ! $(run_as_root) grep -q "stable_secret" "$(SYSCTL_DST)"; then \
		secret_injected=1; reboot_required=1; ( $(inject_ipv6_secrets) ); \
	fi; \
	req=$$(grep "net.ipv6.conf.all.forwarding" "$(SYSCTL_SRC)" | cut -d'=' -f2 | tr -d ' '); \
	actual=$$($(run_as_root) $(SYSCTL_BIN) -n net.ipv6.conf.all.forwarding); \
	if [ "$$req" != "$$actual" ]; then echo "❌ ERROR: Sysctl mismatch!"; exit 1; fi; \
	msg="💎 Convergence verified:"; \
	[ "$$changed" -eq 1 ] && msg="$$msg config updated."; \
	[ "$$secret_injected" -eq 1 ] && msg="$$msg secrets injected."; \
	[ "$$changed" -eq 0 ] && [ "$$secret_injected" -eq 0 ] && msg="$$msg no changes."; \
	[ "$$reboot_required" -eq 1 ] && msg="$$msg ⚠️  REBOOT REQUIRED"; \
	echo "$$msg"

rotate-ipv6-secrets: ensure-run-as-root sysctl-preflight
	@echo "🔄 Forcing IPv6 identity rotation..."
	@set -eu; \
	$(run_as_root) sed -i '/stable_secret/d; /Homelab/d; /rotate/d' "$(SYSCTL_DST)"; \
	( $(inject_ipv6_secrets) ); \
	echo "🚀 Identity rotated. Enforcing system reboot in 5s..."; \
	sleep 5 && $(run_as_root) reboot