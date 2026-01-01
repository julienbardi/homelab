# mk/20_deps.mk
# Package installation and build helpers

GO_MODERN_VERSION := 1.25.5
GO_MODERN_PREFIX  := /usr/local/go
GO_MODERN_BIN     := $(GO_MODERN_PREFIX)/bin/go
STAMP_GO_MODERN   := $(STAMP_DIR)/go-modern.installed

DNSMASQ_CONF_SRC := $(HOMELAB_DIR)/config/dnsmasq/unbound.conf
DNSMASQ_CONF_DST := /etc/dnsmasq.d/unbound.conf

.PHONY: deps install-pkg-go remove-pkg-go \
	install-pkg-pandoc upgrade-pkg-pandoc remove-pkg-pandoc \
	install-pkg-checkmake remove-pkg-checkmake \
	install-pkg-strace remove-pkg-strace \
	install-pkg-vnstat remove-pkg-vnstat \
	install-pkg-tailscale upgrade-pkg-tailscale remove-pkg-tailscale \
	headscale-build \
	install-pkg-dnsmasq remove-pkg-dnsmasq \
	install-dnsmasq-unbound-config remove-dnsmasq-unbound-config

# Aggregate deps target
deps: prereqs \
	install-pkg-go install-pkg-pandoc install-pkg-checkmake install-pkg-strace install-pkg-vnstat \
	install-pkg-tailscale install-pkg-nftables install-pkg-wireguard \
	install-dnsmasq-unbound-config \
	enable-ndppd \
	install-pkg-code-server

# ------------------------------------------------------------
# dnsmasq
# ------------------------------------------------------------
install-pkg-dnsmasq:
	@echo "📦 Installing dnsmasq"
	$(call apt_install,dnsmasq,dnsmasq)
	@$(run_as_root) systemctl enable --now dnsmasq || true
	@echo "✅ dnsmasq installed and enabled"

remove-pkg-dnsmasq:
	@echo "🗑️ Removing dnsmasq"
	@$(run_as_root) systemctl stop dnsmasq || true
	@$(run_as_root) systemctl disable dnsmasq || true
	$(call apt_remove,dnsmasq)
	@echo "✅ dnsmasq removed"

.PHONY: require-unbound-running
require-unbound-running:
	@systemctl is-active --quiet unbound || { \
		echo "❌ Unbound is not running"; exit 1; }

install-dnsmasq-unbound-config: install-pkg-dnsmasq deploy-unbound require-unbound-running
	@echo "📂 Installing dnsmasq → Unbound forwarding config"
	@if [ ! -f "$(DNSMASQ_CONF_SRC)" ]; then \
		echo "❌ Missing $(DNSMASQ_CONF_SRC)"; exit 1; \
	fi
	@$(run_as_root) install -o root -g root -m 0644 \
		"$(DNSMASQ_CONF_SRC)" "$(DNSMASQ_CONF_DST)"
	@$(run_as_root) systemctl restart dnsmasq
	@echo "✅ dnsmasq now forwards DNS to Unbound (127.0.0.1:5335)"

remove-dnsmasq-unbound-config:
	@echo "🗑️ Removing dnsmasq → Unbound forwarding config"
	@$(run_as_root) rm -f "$(DNSMASQ_CONF_DST)"
	@$(run_as_root) systemctl restart dnsmasq || true
	@echo "✅ dnsmasq forwarding config removed"

# ------------------------------------------------------------
# Tailscale repository
# ------------------------------------------------------------
DEBIAN_CODENAME ?= bookworm
TS_REPO_KEYRING := /usr/share/keyrings/tailscale-archive-keyring.gpg
TS_REPO_LIST    := /etc/apt/sources.list.d/tailscale.list

.PHONY: tailscale-repo install-pkg-tailscale upgrade-pkg-tailscale remove-pkg-tailscale verify-pkg-tailscale

tailscale-repo:
	@echo "📦 Adding Tailscale apt repository (Debian $(DEBIAN_CODENAME))"
	@$(run_as_root) install -d -m 0755 /usr/share/keyrings
	@curl -fsSL https://pkgs.tailscale.com/stable/debian/$(DEBIAN_CODENAME).noarmor.gpg \
		| $(run_as_root) install -m 0644 -o root -g root /dev/stdin $(TS_REPO_KEYRING)
	@curl -fsSL https://pkgs.tailscale.com/stable/debian/$(DEBIAN_CODENAME).tailscale-keyring.list \
		| $(run_as_root) install -m 0644 -o root -g root /dev/stdin $(TS_REPO_LIST)
	@$(call apt_update_if_needed)
	@echo "✅ Tailscale repository configured"

install-pkg-tailscale: tailscale-repo
	@echo "📦 Installing Tailscale (client + daemon)"
	@$(call apt_install,tailscale,tailscale)
	@$(run_as_root) systemctl enable tailscaled
	@$(run_as_root) systemctl start tailscaled
	@$(MAKE) FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) verify-pkg-tailscale
	@echo "✅ Tailscale installed and running"

upgrade-pkg-tailscale: tailscale-repo
	@echo "⬆️ Upgrading Tailscale to latest stable"
	@$(call apt_update_if_needed)
	@$(run_as_root) DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y tailscale
	@$(run_as_root) systemctl restart tailscaled
	@$(MAKE) verify-pkg-tailscale
	@echo "✅ Tailscale upgraded"

remove-pkg-tailscale:
	@echo "🗑️ Removing Tailscale"
	@$(run_as_root) systemctl stop tailscaled || true
	@$(run_as_root) systemctl disable tailscaled || true
	@$(call apt_remove,tailscale)
	@echo "✅ Tailscale removed"

verify-pkg-tailscale:
	@echo "🔎 Verifying Tailscale installation"
	@bash -c 'set -e; \
		CLI_VER=$$(tailscale version | head -n1); \
		DS_VER=$$($(run_as_root) tailscaled --version | head -n1); \
		echo "CLI: $$CLI_VER"; echo "DAEMON: $$DS_VER"; \
		if [ "$${CLI_VER}" != "$${DS_VER}" ]; then \
			echo "❌ Version mismatch"; exit 1; \
		fi; \
		echo "✔ Versions aligned" \
	'

# ------------------------------------------------------------
# Go (Debian package)
# ------------------------------------------------------------
install-pkg-go:
	$(call apt_install,go,golang-go)

remove-pkg-go:
	$(call apt_remove,golang-go)

# ------------------------------------------------------------
# Go (modern toolchain)
# ------------------------------------------------------------
.PHONY: install-pkg-go-modern remove-pkg-go-modern verify-pkg-go-modern

install-pkg-go-modern:
	@echo "📦 Installing Go $(GO_MODERN_VERSION) under $(GO_MODERN_PREFIX)"
	@if [ -x "$(GO_MODERN_BIN)" ]; then \
		CUR_VER=$$($(GO_MODERN_BIN) version | awk '{print $$3}' | sed 's/go//'); \
		if [ "$$CUR_VER" = "$(GO_MODERN_VERSION)" ]; then \
			echo "✔ Go $(GO_MODERN_VERSION) already installed"; \
			exit 0; \
		fi; \
	fi
	@tmp=$$(mktemp -d); \
	trap 'rm -rf "$$tmp"' EXIT; \
	curl -fsSL https://go.dev/dl/go$(GO_MODERN_VERSION).linux-amd64.tar.gz \
		-o "$$tmp/go.tar.gz"; \
	$(run_as_root) rm -rf "$(GO_MODERN_PREFIX)"; \
	$(run_as_root) tar -C /usr/local -xzf "$$tmp/go.tar.gz"; \
	echo "version=$(GO_MODERN_VERSION) installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		| $(run_as_root) tee "$(STAMP_GO_MODERN)" >/dev/null
	@echo "✅ Go $(GO_MODERN_VERSION) installed"

verify-pkg-go-modern:
	@$(GO_MODERN_BIN) version

remove-pkg-go-modern:
	@echo "🗑️ Removing Go $(GO_MODERN_PREFIX)"
	@$(run_as_root) rm -rf "$(GO_MODERN_PREFIX)"
	@$(run_as_root) rm -f "$(STAMP_GO_MODERN)"

# ------------------------------------------------------------
# vnstat
# ------------------------------------------------------------
install-pkg-vnstat:
	@echo "📦 Installing vnstat"
	$(call apt_install,vnstat,vnstat)
	@echo "[make] Initializing vnstat database for tailscale0..."
	@if ! $(run_as_root) vnstat --iflist | grep -q tailscale0; then \
		$(run_as_root) vnstat --add -i tailscale0; \
	fi
	@$(run_as_root) systemctl enable --now vnstat || true
	@echo "[make] vnstat installed and initialized for tailscale0"

remove-pkg-vnstat:
	$(call apt_remove,vnstat)

# ------------------------------------------------------------
# nftables
# ------------------------------------------------------------
install-pkg-nftables:
	@echo "📦 Installing nftables"
	$(call apt_install,nftables,nftables)
	@$(run_as_root) systemctl enable --now nftables || true
	@echo "✅ nftables installed and service enabled"

remove-pkg-nftables:
	$(call apt_remove,nftables)

# ------------------------------------------------------------
# WireGuard
# ------------------------------------------------------------
install-pkg-wireguard:
	@echo "📦 Installing WireGuard"
	$(call apt_install,wireguard,wireguard wireguard-tools)
	@echo "✅ WireGuard packages installed"

remove-pkg-wireguard:
	$(call apt_remove,wireguard wireguard-tools)

# ------------------------------------------------------------
# Caddy
# ------------------------------------------------------------
install-pkg-caddy:
	@echo "📦 Installing Caddy"
	@$(run_as_root) rm -f /etc/caddy/Caddyfile
	$(call apt_install,caddy,caddy)

remove-pkg-caddy:
	$(call apt_remove,caddy)

# ------------------------------------------------------------
# Unbound
# ------------------------------------------------------------
install-pkg-unbound:
	@echo "📦 Installing Unbound"
	$(call apt_install,unbound,unbound)
	@$(run_as_root) systemctl enable --now unbound || true
	@echo "✅ Unbound installed and enabled"

remove-pkg-unbound:
	$(call apt_remove,unbound)

# ------------------------------------------------------------
# ndppd
# ------------------------------------------------------------
enable-ndppd: prereqs
	@echo "📦 Enabling ndppd service"
	@$(run_as_root) systemctl enable --now ndppd || true
	@echo "✅ ndppd enabled"

# ------------------------------------------------------------
# checkmake
# ------------------------------------------------------------
CHECKMAKE_VERSION := 0.2.2
CHECKMAKE_BIN := /usr/local/bin/checkmake
STAMP_CHECKMAKE := $(STAMP_DIR)/checkmake.installed

install-pkg-checkmake: install-pkg-pandoc install-pkg-go
	@echo "[make] Installing checkmake (v$(CHECKMAKE_VERSION))"
	@if [ -x "$(CHECKMAKE_BIN)" ]; then \
	  INST_VER=$$($(CHECKMAKE_BIN) --version 2>/dev/null | awk '{print $$2}' || true); \
	  if [ "$$INST_VER" = "$(CHECKMAKE_VERSION)" ]; then \
		echo "[make] checkmake $(CHECKMAKE_VERSION) already installed; skipping"; \
		exit 0; \
	  fi; \
	fi; \
	mkdir -p $(HOME)/src; \
	rm -rf $(HOME)/src/checkmake; \
	git clone --depth 1 --branch v$(CHECKMAKE_VERSION) https://github.com/mrtazz/checkmake.git $(HOME)/src/checkmake; \
	cd $(HOME)/src/checkmake && \
	go build -o checkmake cmd/checkmake/main.go; \
	$(run_as_root) install -m 0755 $(HOME)/src/checkmake/checkmake $(CHECKMAKE_BIN); \
	echo "version=$(CHECKMAKE_VERSION) installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		| $(run_as_root) tee "$(STAMP_CHECKMAKE)" >/dev/null
	@echo "[make] Installed checkmake $(CHECKMAKE_VERSION)"
	@$(CHECKMAKE_BIN) --version

remove-pkg-checkmake:
	$(call remove_cmd,checkmake,rm -f /usr/local/bin/checkmake && rm -rf $(HOME)/src/checkmake && rm -f $(STAMP_CHECKMAKE))

# ------------------------------------------------------------
# strace
# ------------------------------------------------------------
install-pkg-strace:
	$(call apt_install,strace,strace)

remove-pkg-strace:
	$(call apt_remove,strace)

# ------------------------------------------------------------
# Headscale
# ------------------------------------------------------------
HEADSCALE_VERSION ?= v0.27.1

headscale-build: install-pkg-go
	@echo "[make] Building Headscale $(HEADSCALE_VERSION)..."
	@if ! command -v headscale >/dev/null 2>&1; then \
		GOBIN=$(INSTALL_PATH) go install github.com/juanfont/headscale/cmd/headscale@$(HEADSCALE_VERSION); \
	else \
		CURRENT_VER=$$(headscale version | awk '{print $$3}'); \
		if [ "$$CURRENT_VER" != "$(HEADSCALE_VERSION)" ]; then \
			echo "⚠️  A new version has been detected: $$CURRENT_VER"; \
			echo "👉 See https://github.com/juanfont/headscale/releases"; \
		fi; \
		command -v headscale >/dev/null 2>&1 && headscale version; \
	fi

# ------------------------------------------------------------
# Pandoc (pinned .deb)
# ------------------------------------------------------------
PANDOC_VERSION := 3.8.2.1
PANDOC_DEB_URL := https://github.com/jgm/pandoc/releases/download/3.8.2.1/pandoc-3.8.2.1-1-amd64.deb
PANDOC_SHA256 := 5d4ecbf9c616360a9046e14685389ff2898088847e5fb260eedecd023453995a
PANDOC_DEB := /tmp/pandoc-$(PANDOC_VERSION)-amd64.deb
STAMP_PANDOC := $(STAMP_DIR)/pandoc.installed

.SILENT: install-pkg-pandoc

install-pkg-pandoc:
	@$(run_as_root) install -d -m 0755 $(STAMP_DIR); \
	installed_bin=$$(command -v pandoc 2>/dev/null || true); \
	installed_version=$$(dpkg-query -W -f='$${Version}' pandoc 2>/dev/null || true); \
	installed_version_base=$${installed_version%%-*}; \
	if [ -n "$$installed_bin" ] && [ -f "$(PANDOC_DEB)" ] && \
	   [ "$$(sha256sum "$(PANDOC_DEB)" | cut -d' ' -f1)" = "$(PANDOC_SHA256)" ] && \
	   [ "$$installed_version_base" = "$(PANDOC_VERSION)" ]; then \
		echo "[make] pandoc $(PANDOC_VERSION) already installed"; \
		exit 0; \
	fi; \
	rm -f $(PANDOC_DEB); \
	set -euo pipefail; \
	trap 'rm -f "$(PANDOC_DEB)";' EXIT; \
	curl -fsSL "$(PANDOC_DEB_URL)" -o "$(PANDOC_DEB)"; \
	echo "$(PANDOC_SHA256)  $(PANDOC_DEB)" | sha256sum -c - >/dev/null; \
	DEBIAN_FRONTEND=noninteractive $(run_as_root) dpkg -i "$(PANDOC_DEB)" >/dev/null 2>&1 || true; \
	$(run_as_root) DEBIAN_FRONTEND=noninteractive apt-get -y -f install --no-install-recommends >/dev/null; \
	$(run_as_root) apt-mark hold pandoc >/dev/null; \
	installed_version=$$(dpkg-query -W -f='$${Version}' pandoc 2>/dev/null || true); \
	installed_version_base=$${installed_version%%-*}; \
	if [ "$$installed_version_base" != "$(PANDOC_VERSION)" ]; then \
	  echo "[make] ERROR: pandoc wrong version (installed=$$installed_version)"; rm -f "$(PANDOC_DEB)"; trap - EXIT; exit 1; \
	fi; \
	echo "version=$$installed_version sha256=$(PANDOC_SHA256) installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		| $(run_as_root) tee "$(STAMP_PANDOC)" >/dev/null; \
	trap - EXIT; \
	echo "[make] pandoc $(PANDOC_VERSION) installed"

upgrade-pkg-pandoc: $(STAMP_PANDOC)
	@echo "[make] Upgrading pandoc..."
	@$(call apt_update_if_needed)
	@$(run_as_root) DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y pandoc || true
	@tmp=$$(mktemp); dpkg-query -W -f='${Version}\n' pandoc > "$$tmp" 2>/dev/null || echo "unknown" > "$$tmp"; \
	echo "version=$$(cat $$tmp) upgraded_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		| $(run_as_root) tee $(STAMP_PANDOC) >/dev/null; \
	rm -f "$$tmp"
	@echo "[make] pandoc upgrade complete"

remove-pkg-pandoc:
	@echo "[make] Removing pandoc..."
	@if dpkg -s pandoc >/dev/null 2>&1