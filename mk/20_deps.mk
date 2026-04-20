# mk/20_deps.mk
# Package installation and build helpers

GO_MODERN_VERSION := 1.25.5
GO_MODERN_PREFIX  := /usr/local/go
GO_MODERN_BIN     := $(GO_MODERN_PREFIX)/bin/go
STAMP_GO_MODERN   := $(STAMP_DIR)/go-modern.installed
GO_ARCH           := amd64
GO_DIST_URL       := https://go.dev/dl/go$(GO_MODERN_VERSION).linux-$(GO_ARCH).tar.gz

.PHONY: deps install-pkg-go remove-pkg-go \
	install-pkg-pandoc upgrade-pkg-pandoc remove-pkg-pandoc \
	install-pkg-checkmake remove-pkg-checkmake \
	install-pkg-strace remove-pkg-strace \
	install-pkg-vnstat remove-pkg-vnstat \
	install-pkg-tailscale upgrade-pkg-tailscale remove-pkg-tailscale \
	install-pkg-age remove-pkg-age \
	install-pkg-rclone remove-pkg-rclone \
	install-pkg-kopia remove-pkg-kopia \
	headscale-build \
	remove-pkg-dnsmasq

# ------------------------------------------------------------
# Aggregate deps target
# ------------------------------------------------------------
deps: prereqs \
	install-pkg-go install-pkg-pandoc install-pkg-checkmake \
	install-pkg-strace install-pkg-vnstat \
	install-pkg-age install-pkg-rclone install-pkg-kopia \
	install-pkg-sops

# ------------------------------------------------------------
# Tailscale repository
# ------------------------------------------------------------
DEBIAN_CODENAME ?= bookworm
TS_REPO_KEYRING := /usr/share/keyrings/tailscale-archive-keyring.gpg
TS_REPO_LIST    := /etc/apt/sources.list.d/tailscale.list

.PHONY: tailscale-repo install-pkg-tailscale upgrade-pkg-tailscale remove-pkg-tailscale verify-pkg-tailscale

tailscale-repo: ensure-run-as-root
	@echo "📦 Adding Tailscale apt repository (Debian $(DEBIAN_CODENAME))"
	@$(run_as_root) install -d -m 0755 /usr/share/keyrings
	@curl -fsSL https://pkgs.tailscale.com/stable/debian/$(DEBIAN_CODENAME).noarmor.gpg \
	    | $(run_as_root) install -m 0644 -o root -g root /dev/stdin $(TS_REPO_KEYRING)
	@curl -fsSL https://pkgs.tailscale.com/stable/debian/$(DEBIAN_CODENAME).list \
	    | $(run_as_root) install -m 0644 -o root -g root /dev/stdin $(TS_REPO_LIST)
	@$(call apt_update_if_needed)
	@echo "✅ Tailscale repository configured"

install-pkg-tailscale: ensure-run-as-root tailscale-repo verify-pkg-tailscale
	@echo "📦 Installing Tailscale (client + daemon)"
	@$(call apt_install,tailscale,tailscale)
	@$(run_as_root) systemctl enable --now tailscaled >/dev/null 2>&1 || true
	@echo "✅ Tailscale installed and running"

upgrade-pkg-tailscale: ensure-run-as-root tailscale-repo verify-pkg-tailscale
	@echo "⬆️ Upgrading Tailscale to latest stable"
	@$(call apt_update_if_needed)
	@$(run_as_root) DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y tailscale
	@$(run_as_root) systemctl restart tailscaled >/dev/null 2>&1
	@echo "✅ Tailscale upgraded"

remove-pkg-tailscale: ensure-run-as-root
	@echo "🗑️ Removing Tailscale"
	@$(run_as_root) systemctl stop tailscaled >/dev/null 2>&1 || true
	@$(run_as_root) systemctl disable tailscaled >/dev/null 2>&1 || true
	@$(call apt_remove,tailscale)
	@echo "✅ Tailscale removed"

verify-pkg-tailscale: ensure-run-as-root
	@echo "🔍 Verifying Tailscale installation"
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
# Go (Modern Binary Distribution)
# ------------------------------------------------------------
# ------------------------------------------------------------
# Go (Modern Binary Distribution)
# ------------------------------------------------------------
install-pkg-go: ensure-run-as-root
	@if [ -x "$(GO_MODERN_BIN)" ]; then \
		CURRENT_VER=$$($(GO_MODERN_BIN) version | awk '{print $$3}' | sed 's/go//'); \
		if [ "$$CURRENT_VER" = "$(GO_MODERN_VERSION)" ]; then \
			echo "✅ Go $(GO_MODERN_VERSION) already installed at $(GO_MODERN_PREFIX)"; \
			exit 0; \
		fi; \
	fi; \
	if dpkg -l golang-go >/dev/null 2>&1; then \
		echo "🗑️ Removing legacy apt Go version..."; \
		$(run_as_root) apt-get purge -y golang-go golang-1.19-go >/dev/null 2>&1; \
		$(run_as_root) apt-get autoremove -y >/dev/null 2>&1; \
	fi; \
	echo "📦 Downloading and installing Go $(GO_MODERN_VERSION)..."; \
	$(run_as_root) rm -rf $(GO_MODERN_PREFIX); \
	curl -sSL $(GO_DIST_URL) | $(run_as_root) tar -C /usr/local -xz; \
	$(run_as_root) ln -sf $(GO_MODERN_BIN) /usr/local/bin/go; \
	echo "✅ $$(go version) is now installed"

remove-pkg-go: ensure-run-as-root
	@echo "🗑️ Removing Go from $(GO_MODERN_PREFIX)"
	$(run_as_root) rm -rf $(GO_MODERN_PREFIX)
	$(run_as_root) rm -f /usr/local/bin/go

# ------------------------------------------------------------
# vnstat
# ------------------------------------------------------------
install-pkg-vnstat: ensure-run-as-root
	@echo "📦 Installing vnstat"
	$(call apt_install,vnstat,vnstat)
	@echo "Initializing vnstat database for tailscale0..."
	@if ! $(run_as_root) vnstat --iflist | grep -q tailscale0; then \
	    $(run_as_root) vnstat --add -i tailscale0; \
	fi
	@$(run_as_root) systemctl enable --now vnstat >/dev/null 2>&1 || true
	@echo "✅ vnstat installed and initialized for tailscale0"

remove-pkg-vnstat:
	$(call apt_remove,vnstat)

# ------------------------------------------------------------
# nftables
# ------------------------------------------------------------
install-pkg-nftables: ensure-run-as-root
	@echo "📦 Installing nftables"
	$(call apt_install,nft,nftables)
	@$(run_as_root) systemctl enable --now nftables >/dev/null 2>&1 || true
	@echo "✅ nftables installed and service enabled"

remove-pkg-nftables:
	$(call apt_remove,nftables)

# ------------------------------------------------------------
# WireGuard
# ------------------------------------------------------------
install-pkg-wireguard:
	@echo "📦 Installing WireGuard"
	$(call apt_install,wg,wireguard wireguard-tools)
	@echo "✅ WireGuard packages installed"

remove-pkg-wireguard:
	$(call apt_remove,wireguard wireguard-tools)

# ------------------------------------------------------------
# Caddy
# ------------------------------------------------------------
install-pkg-caddy: ensure-run-as-root
	@echo "📦 Installing Caddy"
	@$(run_as_root) rm -f /etc/caddy/Caddyfile
	$(call apt_install,caddy,caddy)

remove-pkg-caddy:
	$(call apt_remove,caddy)

# ------------------------------------------------------------
# Age (Source build via Go)
# ------------------------------------------------------------
AGE_BIN        := /usr/local/bin/age
AGE_KEYGEN_BIN := /usr/local/bin/age-keygen
AGE_VERSION    := v1.2.1

install-pkg-age: install-pkg-go
	@if [ -x "$(AGE_BIN)" ] && $(AGE_BIN) --version 2>&1 | grep -q "$(AGE_VERSION)"; then \
		echo "✅ age $(AGE_VERSION) already installed at $(AGE_BIN)"; \
	else \
		echo "📦 Building age $(AGE_VERSION) from source..."; \
		mkdir -p /tmp/age-build; \
		GOBIN=/tmp/age-build $(GO_MODERN_BIN) install filippo.io/age/cmd/...@$(AGE_VERSION); \
		echo "🚚 Moving binaries to /usr/local/bin (requires root)"; \
		$(run_as_root) install -m 0755 /tmp/age-build/age $(AGE_BIN); \
		$(run_as_root) install -m 0755 /tmp/age-build/age-keygen $(AGE_KEYGEN_BIN); \
		rm -rf /tmp/age-build; \
		echo "✅ age $(AGE_VERSION) installed"; \
	fi

remove-pkg-age:
	@echo "🗑️ Removing age binaries"
	@$(run_as_root) rm -f $(AGE_BIN) $(AGE_KEYGEN_BIN)

# ------------------------------------------------------------
# SOPS (Secrets Operations - Source build via Go)
# ------------------------------------------------------------
SOPS_VERSION := v3.9.4

.PHONY: install-pkg-sops remove-pkg-sops

install-pkg-sops: install-pkg-go
	@if command -v sops >/dev/null 2>&1; then \
		echo "✅ SOPS already installed: $$(sops --version | head -n1)"; \
	else \
		echo "📦 Building SOPS $(SOPS_VERSION) from source..."; \
		mkdir -p /tmp/sops-build; \
		GOBIN=/tmp/sops-build $(GO_MODERN_BIN) install github.com/getsops/sops/v3/cmd/sops@$(SOPS_VERSION); \
		echo "🚚 Moving SOPS to $(INSTALL_PATH)"; \
		$(run_as_root) install -m 0755 /tmp/sops-build/sops $(INSTALL_PATH)/sops; \
		rm -rf /tmp/sops-build; \
		echo "✅ SOPS $(SOPS_VERSION) installed"; \
	fi

remove-pkg-sops:
	@echo "🗑️ Removing SOPS binary"
	@$(run_as_root) rm -f $(INSTALL_PATH)/sops

# ------------------------------------------------------------
# Rclone (The Swiss Army Knife for Cloud Storage)
# ------------------------------------------------------------
install-pkg-rclone: ensure-run-as-root
	@echo "📦 Installing rclone"
	$(call apt_install,rclone,rclone)

remove-pkg-rclone:
	$(call apt_remove,rclone)

# ------------------------------------------------------------
# Kopia (Fast, Encrypted, Deduplicated Backups)
# ------------------------------------------------------------
KOPIA_VERSION := 0.16.0
KOPIA_TARBALL_URL := https://github.com/kopia/kopia/releases/download/v$(KOPIA_VERSION)/kopia-$(KOPIA_VERSION)-linux-x64.tar.gz
KOPIA_TARBALL := /tmp/kopia-$(KOPIA_VERSION)-linux-x64.tar.gz

# SHA256 for kopia-0.16.0-linux-x64.tar.gz
KOPIA_SHA256 := a29f2cc1a49f985d1bfe09340eda0f7ed7b3c98037704da249b47034f1be1a18
# (Replace with the real SHA256 — run: curl -fsSL $URL | sha256sum)
# curl -fsSL https://github.com/kopia/kopia/releases/download/v0.16.0/kopia-0.16.0-linux-x64.tar.gz | sha256sum

.PHONY: fetch-kopia
fetch-kopia: $(INSTALL_URL_FILE_IF_CHANGED)
	@$(INSTALL_URL_FILE_IF_CHANGED) -q \
		"$(KOPIA_TARBALL_URL)" \
		"$(KOPIA_TARBALL)" \
		"$(OPERATOR_USER)" \
		"$(OPERATOR_GROUP)" \
		"0644" \
		"$(KOPIA_SHA256)" || true

STAMP_KOPIA := $(STAMP_DIR_ROOT)/kopia.installed

.PHONY: install-pkg-kopia
install-pkg-kopia: ensure-run-as-root fetch-kopia
	@if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then echo "📦 Installing Kopia $(KOPIA_VERSION)"; fi; \
	set -euo pipefail; \
	TARBALL="$(KOPIA_TARBALL)"; \
	STAMP="$(STAMP_KOPIA)"; \
	VERSION="$(KOPIA_VERSION)"; \
	\
	if command -v kopia >/dev/null 2>&1; then \
		INSTALLED_VER=$$(kopia --version | awk '{print $$1}'); \
		if [ "$$INSTALLED_VER" = "$$VERSION" ]; then \
			if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then echo "ℹ️ kopia $$VERSION already installed"; fi; \
			exit 0; \
		fi; \
	fi; \
	\
	WORKDIR=$$(mktemp -d /tmp/kopia.XXXXXX); \
	tar -xzf "$$TARBALL" -C "$$WORKDIR"; \

	EXTRACT_DIR="$$(find "$$WORKDIR" -maxdepth 1 -type d -name 'kopia-*' | head -n1)"; \

	$(run_as_root) install -m 0755 "$$EXTRACT_DIR/kopia" /usr/local/bin/kopia; \
	rm -rf "$$WORKDIR"; \
	$(run_as_root) rm -f "$(KOPIA_TARBALL)"; \
	\
	tmp_stamp="/tmp/kopia.installed.$$RANDOM"; \
	echo "version=$$VERSION installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$$tmp_stamp"; \
	$(run_as_root) install -m 0644 "$$tmp_stamp" "$$STAMP"; \
	rm -f "$$tmp_stamp"; \
	\
	echo "✅ kopia $$VERSION installed"

.PHONY: remove-pkg-kopia
remove-pkg-kopia: ensure-run-as-root
	@echo "🗑️ Removing Kopia"
	@$(run_as_root) sh -c 'rm -f /usr/local/bin/kopia "$(STAMP_KOPIA)"'
	@echo "✅ Kopia removed"

# ------------------------------------------------------------
# ndppd
# ------------------------------------------------------------
enable-ndppd: ensure-run-as-root prereqs
	@echo "📦 Enabling ndppd service"
	@$(run_as_root) systemctl enable --now ndppd >/dev/null 2>&1 || true
	@echo "✅ ndppd enabled"

# ------------------------------------------------------------
# checkmake
# ------------------------------------------------------------
CHECKMAKE_VERSION := 0.2.2
CHECKMAKE_BIN := /usr/local/bin/checkmake
STAMP_CHECKMAKE := $(STAMP_DIR)/checkmake.installed

install-pkg-checkmake: ensure-run-as-root install-pkg-pandoc install-pkg-go
	@echo "📦 Installing checkmake (v$(CHECKMAKE_VERSION))"
	@if [ -f "$(STAMP_CHECKMAKE)" ]; then \
	    INST_VER=$$(grep '^version=' "$(STAMP_CHECKMAKE)" | cut -d= -f2); \
	    if [ "$$INST_VER" = "$(CHECKMAKE_VERSION)" ]; then \
	        echo "checkmake $(CHECKMAKE_VERSION) already installed; skipping"; \
	        exit 0; \
	    fi; \
	fi; \
	mkdir -p $(HOME)/src; \
	rm -rf $(HOME)/src/checkmake; \
	git clone --quiet --depth 1 --branch v$(CHECKMAKE_VERSION) \
	    https://github.com/mrtazz/checkmake.git $(HOME)/src/checkmake >/dev/null 2>&1; \
	cd $(HOME)/src/checkmake >/dev/null 2>&1 && \
	go build -o checkmake cmd/checkmake/main.go >/dev/null 2>&1; \
	$(run_as_root) install -m 0755 $(HOME)/src/checkmake/checkmake $(CHECKMAKE_BIN); \
	echo "version=$(CHECKMAKE_VERSION) installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	    | $(run_as_root) tee "$(STAMP_CHECKMAKE)" >/dev/null
	@echo "✅ Installed checkmake $(CHECKMAKE_VERSION)"

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
	@echo "� ️ Building Headscale $(HEADSCALE_VERSION)..."
	@if ! command -v headscale >/dev/null 2>&1; then \
	    GOBIN=$(INSTALL_PATH) go install github.com/juanfont/headscale/cmd/headscale@$(HEADSCALE_VERSION); \
	else \
	    CURRENT_VER=$$(headscale version | awk '{print $$3}'); \
	    if [ "$$CURRENT_VER" != "$(HEADSCALE_VERSION)" ]; then \
	        echo "� ️  A new version has been detected: $$CURRENT_VER"; \
	        echo "👉 See https://github.com/juanfont/headscale/releases"; \
	    fi; \
	    command -v headscale >/dev/null 2>&1 && headscale version; \
	fi

# ------------------------------------------------------------
# Pandoc (pinned .deb)
# ------------------------------------------------------------
#PANDOC_VERSION := 3.8.2.1
#PANDOC_DEB_URL := https://github.com/jgm/pandoc/releases/download/3.8.2.1/pandoc-3.8.2.1-1-amd64.deb
#PANDOC_SHA256 := 5d4ecbf9c616360a9046e14685389ff2898088847e5fb260eedecd023453995a

PANDOC_VERSION := 3.9.0.2
PANDOC_DEB_URL := https://github.com/jgm/pandoc/releases/download/3.9.0.2/pandoc-3.9.0.2-1-amd64.deb
PANDOC_SHA256  := ce4ac48f48aa7eadc1f5dbdf3449a1739f188ecb8c5421c5adc070fe7479e567


PANDOC_DEB := /tmp/pandoc-$(PANDOC_VERSION)-amd64.deb
STAMP_PANDOC := $(STAMP_DIR_ROOT)/pandoc.installed

.PHONY: fetch-pandoc
fetch-pandoc: $(INSTALL_URL_FILE_IF_CHANGED)
	@$(INSTALL_URL_FILE_IF_CHANGED) \
		"$(PANDOC_DEB_URL)" \
		"$(PANDOC_DEB)" \
		"$(OPERATOR_USER)" \
		"$(OPERATOR_GROUP)" \
		"0644" \
		"$(PANDOC_SHA256)" || true

.SILENT: install-pkg-pandoc

.PHONY: install-pkg-pandoc
install-pkg-pandoc: fetch-pandoc
	@echo "📦 install-pkg-pandoc"
	@# Ensure system-wide stamp directory exists
	@$(run_as_root) install -d -m 0755 "$(STAMP_DIR_ROOT)"

	@set -euo pipefail; \
	DEB="$(PANDOC_DEB)"; \
	SHA="$(PANDOC_SHA256)"; \
	VERSION="$(PANDOC_VERSION)"; \
	STAMP="$(STAMP_PANDOC)"; \
	\
	installed_bin=$$(command -v pandoc 2>/dev/null || true); \
	installed_version=$$(dpkg-query -W -f='$${Version}' pandoc 2>/dev/null || true); \
	installed_version_base=$${installed_version%%-*}; \
	\
	if [ -n "$$installed_bin" ] && \
	[ -f "$$DEB" ] && \
	[ "$$(sha256sum "$$DEB" | cut -d" " -f1)" = "$$SHA" ] && \
	[ "$$installed_version_base" = "$$VERSION" ]; then \
		echo "ℹ️ pandoc $$VERSION already installed"; \
		exit 0; \
	fi; \
	\
	echo "$$SHA  $$DEB" | sha256sum -c - >/dev/null; \
	\
	DEBIAN_FRONTEND=noninteractive $(run_as_root) dpkg -i "$$DEB" >/dev/null 2>&1 || true; \
	$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get -y -f install --no-install-recommends >/dev/null; \
	$(run_as_root) apt-mark hold pandoc >/dev/null; \
	\
	installed_version=$$(dpkg-query -W -f='$${Version}' pandoc 2>/dev/null || true); \
	installed_version_base=$${installed_version%%-*}; \
	if [ "$$installed_version_base" != "$$VERSION" ]; then \
		echo "❌ ERROR: pandoc wrong version (installed=$$installed_version)"; \
		exit 1; \
	fi; \
	\
	tmp_stamp="/tmp/pandoc.installed.$$RANDOM"; \
	echo "version=$$installed_version sha256=$$SHA installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$$tmp_stamp"; \
	$(run_as_root) install -m 0644 "$$tmp_stamp" "$$STAMP"; \
	rm -f "$$tmp_stamp"; \
	\
	echo "✅ pandoc $$VERSION installed"


upgrade-pkg-pandoc: ensure-run-as-root $(STAMP_PANDOC)
	@echo "⬆️ Upgrading pandoc..."
	@$(call apt_update_if_needed)
	@$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y pandoc || true
	@tmp=$$(mktemp); dpkg-query -W -f='${Version}\n' pandoc > "$$tmp" 2>/dev/null || echo "unknown" > "$$tmp"; \
	echo "version=$$(cat $$tmp) upgraded_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		| $(run_as_root) tee $(STAMP_PANDOC) >/dev/null; \
	rm -f "$$tmp"
	@echo "✅ pandoc upgrade complete"

remove-pkg-pandoc: ensure-run-as-root
	@if dpkg -s pandoc >/dev/null 2>&1; then \
		echo "🗑️ Removing pandoc (takes about 4 seconds)..."
		$(run_as_root) apt-get remove -y --allow-change-held-packages pandoc >/dev/null 2>&1; \
	fi
