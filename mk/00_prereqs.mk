# mk/00_prereqs.mk
# ------------------------------------------------------------
# Core tooling used across scripts
# ------------------------------------------------------------
# This file must be run before any router, firewall, or WireGuard targets.

TAILSCALE_KEYRING := /usr/share/keyrings/tailscale-archive-keyring.gpg
TAILSCALE_KEY_URL := https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg

TAILSCALE_REPO_FILE := /etc/apt/sources.list.d/tailscale.list
TAILSCALE_REPO_LINE := deb [signed-by=$(TAILSCALE_KEYRING)] https://pkgs.tailscale.com/stable/debian bookworm main

.PHONY: prereqs-network prereqs fix-tailscale-repo

# minimum required to route packets
prereqs-network: ensure-run-as-root
	@echo "[make] Installing base networking prerequisites"
	@$(run_as_root) apt-get update
	@$(run_as_root) apt-get install -y \
		wireguard \
		wireguard-tools \
		netfilter-persistent \
		iptables-persistent \
		ethtool \
		tcpdump

# everything else
prereqs: ensure-run-as-root prereqs-network
	@echo "[check] Verifying public DNS CNAME for apt.bardi.ch by asking a public DNS"
	@cname=$$(dig +short @1.1.1.1 apt.bardi.ch CNAME | sed 's/\.$$//'); \
	if [ "$$cname" != "bardi.ch" ]; then \
		echo "❌ ERROR: Public DNS misconfiguration detected"; \
		echo "   Expected: apt.bardi.ch → CNAME bardi.ch."; \
		echo "   Found:    apt.bardi.ch → '$${cname:-<none>}'"; \
		echo ""; \
		echo "👉 Fix this in Infomaniak DNS before continuing:"; \
		echo "   apt 21600 IN CNAME bardi.ch."; \
		exit 1; \
	fi
	@echo "✅ Public DNS CNAME for apt.bardi.ch is correct"

	# APT trust bootstrap for third-party repositories (must run before any apt install)
	@echo "[make] Ensuring Tailscale APT signing key"
	@if [ -f $(TAILSCALE_KEYRING) ]; then \
		echo "ℹ️  Tailscale key already present"; \
	else \
		echo "➕ Installing Tailscale signing key"; \
		curl -fsSL $(TAILSCALE_KEY_URL) | \
			$(run_as_root) tee $(TAILSCALE_KEYRING) >/dev/null
	fi

	@echo "[check] Verifying Tailscale repo uses signed-by"
	@if grep -Rq "pkgs.tailscale.com" /etc/apt/sources.list.d; then \
		if grep -Rq "pkgs.tailscale.com" /etc/apt/sources.list.d \
			| xargs grep -L "signed-by=$(TAILSCALE_KEYRING)" >/dev/null; then \
			echo "❌ Tailscale repo missing signed-by=$(TAILSCALE_KEYRING)"; \
			echo ""; \
			echo "👉 To repair this, run:"; \
			echo "   make fix-tailscale-repo"; \
			echo "   make prereqs"; \
			echo "   sudo apt-get update"; \
			exit 1; \
		fi; \
	else \
		echo "ℹ️  No Tailscale repo configured yet"; \
	fi

	# apt-cacher-ng: local APT proxy for homelab clients
	@echo "[make] Ensuring installation of prerequisite tools"
	@$(call apt_update_if_needed)
	@$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
		build-essential \
		curl jq git nftables iptables shellcheck pup codespell aspell ndppd \
		knot-dnsutils \
		unbound dnsutils dnsperf \
		iperf3 \
		qrencode \
		libc-ares-dev \
		apt-cacher-ng
	@echo "✅ [make] Base prerequisites installed"

fix-tailscale-repo: ensure-run-as-root
	@echo "🛠️  Fixing Tailscale APT repository (signed-by hygiene)"
	@test -f $(TAILSCALE_REPO_FILE) || { \
		echo "❌ $(TAILSCALE_REPO_FILE) not found"; \
		exit 1; \
	}
	@$(run_as_root) sed -i \
		's|^deb .*pkgs.tailscale.com.*|$(TAILSCALE_REPO_LINE)|' \
		$(TAILSCALE_REPO_FILE)
	@echo "✅ Tailscale repo updated with signed-by=$(TAILSCALE_KEYRING)"
