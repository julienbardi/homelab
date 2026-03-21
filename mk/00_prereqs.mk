# mk/00_prereqs.mk
# Core tooling used across scripts
# ------------------------------------------------------------
# CONTRACT:
# - prereqs-* targets may mutate system state
# - *-verify targets never mutate state
# - installs must be idempotent
# - failures must be explicit and actionable
#
# This file must be run before any router, firewall, or WireGuard targets.
# ROLE gates prerequisites by responsibility: routers must manage NICs; services must not.
# ------------------------------------------------------------

.PHONY: prereqs prereqs-network prereqs-network-verify \
	prereqs-docs-verify prereqs-public-dns-verify \
	prereqs-root-ssh-key prereqs-operator-ssh-key \
	install-ssh-config fix-tailscale-repo \
	rust-system prereqs-python-venv prereqs-python-venv-verify \
	prereqs-dns-health-check-verify prereqs-tailscale-repo-verify \
	prereqs-helper-scripts

PREREQ_PKGS := build-essential curl jq git nftables iptables shellcheck \
			   pup codespell aspell aspell-en ndppd knot-dnsutils \
			   unbound dnsutils dnsperf iperf3 qrencode ripgrep htop \
			   libc-ares-dev apt-cacher-ng unzip

# ------------------------------------------------------------
# Network & System Verification
# ------------------------------------------------------------

prereqs-network-verify:
	@command -v wg >/dev/null || { echo "❌ wireguard missing"; exit 1; }
ifeq ($(ROLE),router)
	@command -v ethtool >/dev/null || { \
		echo "❌ ethtool missing (required for ROLE=router)"; exit 1; }
	@sysctl net.ipv4.ip_forward >/dev/null || \
		echo "⚠️  Cannot read net.ipv4.ip_forward (sysctl unavailable?)"
else
	@command -v ethtool >/dev/null || \
		echo "ℹ️  ethtool not required for ROLE=$(ROLE)"
endif

prereqs-public-dns-verify:
	@echo "🔍 Verifying public DNS CNAME for apt.bardi.ch"
	@cname=$$(dig +short @$(PUBLIC_DNS) apt.bardi.ch CNAME | sed 's/\.$$//'); \
	if [ "$$cname" != "$(APT_CNAME_EXPECTED)" ]; then \
		echo "❌ ERROR: Public DNS misconfiguration detected"; \
		echo "   Expected: apt.bardi.ch -> CNAME $(APT_CNAME_EXPECTED)."; \
		echo "   Found:    apt.bardi.ch -> '$${cname:-<none>}'"; \
		echo ""; \
		echo "👉 Fix this in Infomaniak DNS before continuing:"; \
		echo "   apt 21600 IN CNAME $(APT_CNAME_EXPECTED)."; \
		exit 1; \
	fi
	@echo "✅ Public DNS CNAME is correct"

prereqs-tailscale-repo-verify:
	@echo "🔍 Verifying Tailscale repo hygiene"
	@if [ -f $(TAILSCALE_REPO_FILE) ]; then \
		bad=$$(grep -Rl "pkgs.tailscale.com" /etc/apt/sources.list.d \
			| xargs -r grep -L "signed-by=$(TAILSCALE_KEYRING)"); \
		if [ -n "$$bad" ]; then \
			echo "❌ Tailscale repo missing signed-by=$(TAILSCALE_KEYRING):"; \
			echo "$$bad"; \
			echo ""; \
			echo "👉 To repair this, run:"; \
			echo "   make fix-tailscale-repo"; \
			exit 1; \
		fi; \
	fi
	@echo "✅ Tailscale repo hygiene check passed"

# ------------------------------------------------------------
# Main Prereqs Target
# ------------------------------------------------------------

prereqs: \
	ensure-run-as-root \
	prereqs-public-dns-verify \
	prereqs-tailscale-repo-verify \
	prereqs-network \
	$(HOMELAB_ENV_DST) \
	prereqs-dns-warm-verify \
	prereqs-docs-verify \
	prereqs-helper-scripts \
	install-ssh-config
	# APT trust bootstrap for third-party repositories
	@echo "🔐 Ensuring Tailscale APT signing key"
	@curl -fsSL $(TAILSCALE_KEY_URL) -o /tmp/tailscale.key
	@$(call install_file,/tmp/tailscale.key,$(TAILSCALE_KEYRING),root,root,644)
	@rm -f /tmp/tailscale.key

	@echo "📦 Ensuring installation of prerequisite tools"
	@$(call apt_update_if_needed)
	@$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
		$(PREREQ_PKGS)

	@for bin in curl jq git iperf3 qrencode funzip; do \
		command -v $$bin >/dev/null || { \
			echo "❌ $$bin missing after install"; exit 1; }; \
	done
	@test -x /usr/sbin/nft || { \
		echo "❌ nft binary missing at /usr/sbin/nft"; exit 1; }
	@echo "✅ Base prerequisites installed"

# ------------------------------------------------------------
# Network & Infrastructure Mutators
# ------------------------------------------------------------

prereqs-network: ensure-run-as-root prereqs-network-verify
	@echo "📦 Installing base networking prerequisites"
	@$(call apt_update_if_needed)
	@$(run_as_root) apt-get install -y --no-install-recommends \
		wireguard wireguard-tools netfilter-persistent iptables-persistent ethtool tcpdump

fix-tailscale-repo: ensure-run-as-root
	@echo "⚠️  Fixing Tailscale APT repository (signed-by hygiene)"
	@test -f $(TAILSCALE_REPO_FILE) || { echo "❌ $(TAILSCALE_REPO_FILE) not found"; exit 1; }
	@$(run_as_root) sed -i 's|^deb .*pkgs.tailscale.com.*|$(TAILSCALE_REPO_LINE)|' $(TAILSCALE_REPO_FILE)
	@echo "✅ Tailscale repo updated with signed-by=$(TAILSCALE_KEYRING)"

# ------------------------------------------------------------
# SSH & Identity
# ------------------------------------------------------------

prereqs-root-ssh-key:
	@key=/root/.ssh/id_ed25519; \
	if sudo test -f $$key; then \
		echo "ℹ️  Root SSH key already present"; \
	else \
		host=$$(hostname -s); \
		comment="$$host-root-$$(date +%F)"; \
		echo "➕ Generating root SSH key ($$comment)"; \
		sudo mkdir -p -m 700 /root/.ssh; \
		sudo ssh-keygen -t ed25519 -f $$key -N "" -C "$$comment" </dev/null; \
		sudo chmod 600 $$key; \
		sudo chmod 644 $$key.pub; \
	fi

prereqs-operator-ssh-key:
	@key=$$HOME/.ssh/id_ed25519; \
	if [ -f $$key ]; then \
		echo "ℹ️  Operator SSH key already present"; \
	else \
		host=$$(hostname -s); \
		user=$$(id -un); \
		comment="$$host-operator-$$user-$$(date +%F)"; \
		echo "➕ Generating operator SSH key ($$comment)"; \
		mkdir -p -m 700 $$HOME/.ssh; \
		ssh-keygen -t ed25519 -f $$key -N "" -C "$$comment"; \
		chmod 600 $$key; \
		chmod 644 $$key.pub; \
	fi

install-ssh-config: prereqs-operator-ssh-key
	@echo "🔧 Ensuring SSH config is up to date"
	@sudo install -d -m 700 $(OPERATOR_HOME)/.ssh
	@sudo chown $(OPERATOR_USER):$(OPERATOR_GROUP) $(OPERATOR_HOME)/.ssh
	@$(call install_file,$(MAKEFILE_DIR)config/ssh_config,$(OPERATOR_HOME)/.ssh/config,$(OPERATOR_USER),$(OPERATOR_GROUP),600)

# ------------------------------------------------------------
# Extended Tooling (Rust, Python, Scripts)
# ------------------------------------------------------------

rust-system: ensure-run-as-root
	@command -v cargo >/dev/null 2>&1 || { \
		echo "📦 Installing Rust system-wide"; \
		$(run_as_root) sh -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path'; \
		$(run_as_root) ln -sf /root/.cargo/bin/cargo "$(INSTALL_PATH)/cargo"; \
		$(run_as_root) ln -sf /root/.cargo/bin/rustc "$(INSTALL_PATH)/rustc"; \
	}

prereqs-python-venv-verify:
	@python3 -c 'import venv' >/dev/null 2>&1 || { \
		echo "❌ python3-venv missing"; \
		echo "➡️  Fix with: make prereqs-python-venv"; \
		exit 1; \
	}

prereqs-python-venv: ensure-run-as-root prereqs-python-venv-verify
	@echo "➕ Ensuring python3-venv is installed"
	@$(call apt_update_if_needed)
	@$(run_as_root) apt-get install -y --no-install-recommends python3-venv

prereqs-dns-health-check-verify: ensure-run-as-root
	@$(run_as_root) $(INSTALL_PATH)/dns-health-check.sh --check-only || { \
		echo "❌ DNS health check script drift detected"; \
		echo "➡️  Remediate with: sudo make install-all"; \
		exit 1; \
	}

# ------------------------------------------------------------
# Helper scripts
# ------------------------------------------------------------

prereqs-helper-scripts: ensure-run-as-root
	@echo "📦 Ensuring helper scripts are installed"
	@$(run_as_root) install -d -o root -g root -m 0755 $(INSTALL_PATH)
	@$(run_as_root) install -o root -g root -m 0755 \
		$(MAKEFILE_DIR)scripts/ensure_dir.sh \
		$(INSTALL_PATH)/ensure_dir.sh
