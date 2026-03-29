# mk/20_sysctl.mk
.PHONY: install-homelab-sysctl rotate-ipv6-secrets

# --- CONFIGURATION & PATHS ---
REPO_ROOT ?= ./
THIS_FILE  := $(REPO_ROOT)mk/20_sysctl.mk
SYSCTL_SRC := config/sysctl.d/99-homelab-forwarding.conf
SYSCTL_DST := /etc/sysctl.d/99-homelab-forwarding.conf
SYSCTL_BIN := /sbin/sysctl

# --- OPERATOR-GRADE MACROS (Subshell-Safe) ---
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
	echo "--------------------------------------------------------"; \
	echo "⚠️  REBOOT REQUIRED: IPv6 Stable Secrets generated."; \
	echo "--------------------------------------------------------"; \
}
endef

# --- TARGET: install-homelab-sysctl ---
install-homelab-sysctl: ensure-run-as-root
	@#echo "🧩 Reconciling sysctl configuration..."
	@set -eu; \
	changed=0; \
	secret_injected=0; \
	reboot_required=0; \
	if [ ! -f "$(SYSCTL_DST)" ]; then \
		changed=1; \
	else \
		# PORTABLE STRIP-DIFF ENGINE \
		tmp_src=$$(mktemp); tmp_dst=$$(mktemp); \
		sed '/^[[:space:]]*#/d; /^[[:space:]]*$$/d' "$(SYSCTL_SRC)" > "$$tmp_src"; \
		$(run_as_root) sed '/stable_secret/d; /Homelab/d; /rotate/d; /^[[:space:]]*#/d; /^[[:space:]]*$$/d' "$(SYSCTL_DST)" > "$$tmp_dst"; \
		if ! diff -qwb "$$tmp_src" "$$tmp_dst" >/dev/null 2>&1; then changed=1; fi; \
		rm -f "$$tmp_src" "$$tmp_dst"; \
	fi; \
	if [ "$$changed" -eq 1 ]; then \
		( $(apply_sysctl_file) ); \
	fi; \
	if ! $(run_as_root) grep -q "stable_secret" "$(SYSCTL_DST)"; then \
		secret_injected=1; \
		reboot_required=1; \
		( $(inject_ipv6_secrets) ); \
	fi; \
	# POST-APPLY VALIDATION \
	req=$$(grep "net.ipv6.conf.all.forwarding" "$(SYSCTL_SRC)" | cut -d'=' -f2 | tr -d ' '); \
	actual=$$($(run_as_root) $(SYSCTL_BIN) -n net.ipv6.conf.all.forwarding); \
	if [ "$$req" != "$$actual" ]; then \
		echo "❌ ERROR: Sysctl mismatch! Expected $$req, got $$actual."; \
		exit 1; \
	fi; \
	# --- OPERATOR-GRADE SUMMARY --- \
	msg="💎 Convergence verified:"; \
	if [ "$$changed" -eq 1 ] && [ "$$secret_injected" -eq 1 ]; then \
		msg="$$msg functional config updated + secrets injected."; \
	elif [ "$$changed" -eq 1 ]; then \
		msg="$$msg functional config updated."; \
	elif [ "$$secret_injected" -eq 1 ]; then \
		msg="$$msg secrets injected."; \
	else \
		msg="$$msg no changes."; \
	fi; \
	if [ "$$reboot_required" -eq 1 ]; then \
		msg="$$msg ⚠️  REBOOT REQUIRED"; \
	fi; \
	echo "$$msg"

# --- TARGET: rotate-ipv6-secrets ---
rotate-ipv6-secrets: ensure-run-as-root
	@echo "🔄 Forcing IPv6 identity rotation..."
	@set -eu; \
	$(run_as_root) sed -i '/stable_secret/d; /Homelab/d; /rotate/d' "$(SYSCTL_DST)"; \
	( $(inject_ipv6_secrets) ); \
	echo "🚀 Identity rotated. Enforcing system reboot in 5s..."; \
	sleep 5 && $(run_as_root) reboot
