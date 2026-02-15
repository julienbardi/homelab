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
# NON-GOAL:
# - This file does NOT cache system package state
# - Capability checks are intentionally re-evaluated on each invocation
# ------------------------------------------------------------
.PHONY: prereqs-network prereqs-network-verify \
	prereqs-docs-verify \
	prereqs fix-tailscale-repo \
	rust-system

prereqs-network-verify:
	@command -v wg >/dev/null || { echo "❌ wireguard missing"; exit 1; }
ifeq ($(ROLE),router)
	@command -v ethtool >/dev/null || { \
		echo "❌ ethtool missing (required for ROLE=router)"; exit 1; }
else
	@command -v ethtool >/dev/null || \
		echo "ℹ️  ethtool not required for ROLE=$(ROLE)"
endif
ifeq ($(ROLE),router)
	@sysctl net.ipv4.ip_forward >/dev/null || \
		echo "⚠️  Cannot read net.ipv4.ip_forward (sysctl unavailable?)"
endif

# minimum required to route packets
prereqs-network: ensure-run-as-root prereqs-network-verify
	@echo "Installing base networking prerequisites"
	@$(run_as_root) apt-get update
	@$(run_as_root) apt-get install -y \
		wireguard \
		wireguard-tools \
		netfilter-persistent \
		iptables-persistent \
		ethtool \
		tcpdump

# everything else
prereqs-docs-verify:
	@command -v glow >/dev/null || \
		echo "ℹ️  glow not installed (Markdown help will be shown raw)"

prereqs: ensure-run-as-root prereqs-network $(HOMELAB_ENV_DST)
	@echo "[check] Verifying public DNS CNAME for apt.bardi.ch by asking a public DNS"
	@cname=$$(dig +short @$(PUBLIC_DNS) apt.bardi.ch CNAME | sed 's/\.$$//'); \
	if [ "$$cname" != "$(APT_CNAME_EXPECTED)" ]; then \
		echo "❌ ERROR: Public DNS misconfiguration detected"; \
		echo "   Expected: apt.bardi.ch → CNAME $(APT_CNAME_EXPECTED)."; \
		echo "   Found:    apt.bardi.ch → '$${cname:-<none>}'"; \
		echo ""; \
		echo "👉 Fix this in Infomaniak DNS before continuing:"; \
		echo "   apt 21600 IN CNAME $(APT_CNAME_EXPECTED)."; \
		exit 1; \
	fi
	@echo "✅ Public DNS CNAME for apt.bardi.ch is correct"

	# APT trust bootstrap for third-party repositories (must run before any apt install)
	@echo "Ensuring Tailscale APT signing key"
	@if [ -f $(TAILSCALE_KEYRING) ]; then \
		echo "ℹ️  Tailscale key already present"; \
	else \
		echo "➕ Installing Tailscale signing key"; \
		curl -fsSL $(TAILSCALE_KEY_URL) | \
			$(run_as_root) tee $(TAILSCALE_KEYRING) >/dev/null; \
	fi

	@echo "[check] Verifying Tailscale repo uses signed-by"
	@bad=$$(grep -Rl "pkgs.tailscale.com" /etc/apt/sources.list.d \
		| xargs -r grep -L "signed-by=$(TAILSCALE_KEYRING)"); \
	if [ -n "$$bad" ]; then \
		echo "❌ Tailscale repo missing signed-by=$(TAILSCALE_KEYRING):"; \
		echo "$$bad"; \
		echo ""; \
		echo "👉 To repair this, run:"; \
		echo "   make fix-tailscale-repo"; \
		echo "   make prereqs"; \
		echo "   sudo apt-get update"; \
		exit 1; \
	else \
		echo "ℹ️  No Tailscale repo configured yet"; \
	fi

	# apt-cacher-ng: local APT proxy for homelab clients
	@echo "Ensuring installation of prerequisite tools"
	@$(call apt_update_if_needed)
	@$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
		build-essential \
		curl jq git nftables iptables shellcheck pup codespell aspell aspell-en ndppd \
		knot-dnsutils \
		unbound dnsutils dnsperf \
		iperf3 \
		qrencode \
		libc-ares-dev \
		apt-cacher-ng
	@for bin in curl jq git iperf3 qrencode; do \
		command -v $$bin >/dev/null || { \
			echo "❌ $$bin missing after install"; exit 1; }; \
	done
	@test -x /usr/sbin/nft || { \
		echo "❌ nft binary missing at /usr/sbin/nft"; exit 1; }
	@echo "✅ Base prerequisites installed"

fix-tailscale-repo: ensure-run-as-root
	@echo "🛠️ Fixing Tailscale APT repository (signed-by hygiene)"
	@test -f $(TAILSCALE_REPO_FILE) || { \
		echo "❌ $(TAILSCALE_REPO_FILE) not found"; \
		exit 1; \
	}
	@$(run_as_root) sed -i \
		's|^deb .*pkgs.tailscale.com.*|$(TAILSCALE_REPO_LINE)|' \
		$(TAILSCALE_REPO_FILE)
	@echo "✅ Tailscale repo updated with signed-by=$(TAILSCALE_KEYRING)"

# ------------------------------------------------------------
# Rust toolchain (system-wide, use as dependency when needed, e.g. attic)
# Installed via rustup but exposed system-wide via /usr/local/bin
# rustup installs into /root/.cargo; binaries are symlinked into /usr/local/bin
# ------------------------------------------------------------
rust-system: ensure-run-as-root
	@command -v cargo >/dev/null 2>&1 || { \
		echo "→ Installing Rust system-wide"; \
		$(run_as_root) sh -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path'; \
		$(run_as_root) ln -sf /root/.cargo/bin/cargo /usr/local/bin/cargo; \
		$(run_as_root) ln -sf /root/.cargo/bin/rustc /usr/local/bin/rustc; \
	}

.PHONY: prereqs-python-venv-verify
prereqs-python-venv-verify:
	@python3 -c 'import venv' >/dev/null 2>&1 || { \
		echo "❌ python3-venv missing"; \
		echo "➡️  Required for WireGuard Python compiler"; \
		echo "➡️  Fix with: make prereqs-python-venv"; \
		exit 1; \
	}

.PHONY: prereqs-python-venv
prereqs-python-venv: ensure-run-as-root prereqs-python-venv-verify
	@echo "➕ Ensuring python3-venv is installed"
	@$(call apt_update_if_needed)
	@$(run_as_root) apt-get install -y --no-install-recommends python3-venv
