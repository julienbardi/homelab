# mk/20_deps.mk
# Package installation and build helpers

.PHONY: deps install-pkg-go remove-pkg-go \
	install-pkg-pandoc upgrade-pkg-pandoc remove-pkg-pandoc \
	install-pkg-checkmake remove-pkg-checkmake \
	install-pkg-strace remove-pkg-strace \
	install-pkg-vnstat remove-pkg-vnstat \
	install-pkg-tailscale upgrade-pkg-tailscale remove-pkg-tailscale \
	headscale-build

# Aggregate deps target, not used: install-pkg-caddy
deps: install-pkg-go install-pkg-pandoc install-pkg-checkmake install-pkg-strace install-pkg-vnstat \
	install-pkg-tailscale install-pkg-nftables install-pkg-wireguard build-caddy-custom verify-caddy install-pkg-unbound install-pkg-ndppd \
	install-pkg-shellcheck install-pkg-codespell install-pkg-aspell \
	install-pkg-code-server

# Tailscale (client + daemon) via apt repository

DEBIAN_CODENAME ?= bookworm
TS_REPO_KEYRING := /usr/share/keyrings/tailscale-archive-keyring.gpg
TS_REPO_LIST    := /etc/apt/sources.list.d/tailscale.list

.PHONY: tailscale-repo install-pkg-tailscale upgrade-pkg-tailscale remove-pkg-tailscale verify-pkg-tailscale

tailscale-repo:
	@echo "📦 Adding Tailscale apt repository (Debian $(DEBIAN_CODENAME))"
	@sudo mkdir -p --mode=0755 /usr/share/keyrings
	@curl -fsSL https://pkgs.tailscale.com/stable/debian/$(DEBIAN_CODENAME).noarmor.gpg \
		| sudo install -m 0644 -o root -g root /dev/stdin $(TS_REPO_KEYRING)
	@curl -fsSL https://pkgs.tailscale.com/stable/debian/$(DEBIAN_CODENAME).tailscale-keyring.list \
		| sudo install -m 0644 -o root -g root /dev/stdin $(TS_REPO_LIST)

	@# Update apt cache (use cached helper to avoid repeated full updates)
	@$(call apt_update_if_needed)
	@echo "✅ Tailscale repository configured"

install-pkg-tailscale: tailscale-repo
	@echo "📦 Installing Tailscale (client + daemon)"
	@sudo apt-get install -y tailscale
	@sudo systemctl enable tailscaled
	@sudo systemctl start tailscaled
	@$(MAKE) FORCE=$(FORCE) CONF_FORCE=$(CONF_FORCE) verify-pkg-tailscale
	@echo "✅ Tailscale installed and running"

upgrade-pkg-tailscale: tailscale-repo
	@echo "⬆️ Upgrading Tailscale to latest stable"
	@$(call apt_update_if_needed)
	@sudo apt-get install -y --only-upgrade tailscale
	@sudo systemctl restart tailscaled
	@$(MAKE) verify-pkg-tailscale
	@echo "✅ Tailscale upgraded"

remove-pkg-tailscale:
	@echo "🗑️ Removing Tailscale"
	@sudo systemctl stop tailscaled || true
	@sudo systemctl disable tailscaled || true
	@sudo apt-get remove --purge -y tailscale || true
	@echo "✅ Tailscale removed"

verify-pkg-tailscale:
	@echo "🔎 Verifying Tailscale installation"
	@bash -c 'set -e; \
		CLI_VER=$$(tailscale version | head -n1); \
		DS_VER=$$(sudo tailscaled --version | head -n1); \
		echo "CLI: $$CLI_VER"; echo "DAEMON: $$DS_VER"; \
		if [ "$${CLI_VER}" != "$${DS_VER}" ]; then \
			echo "❌ Version mismatch"; exit 1; \
		fi; \
		echo "✔ Versions aligned" \
	'


# Use apt_install macro from mk/01_common.mk
install-pkg-go:
	$(call apt_install,go,golang-go)

remove-pkg-go:
	$(call apt_remove,golang-go)

# vnstat (network traffic monitor)
install-pkg-vnstat:
	@echo "📦 Installing vnstat (network traffic monitor)"
	$(call apt_install,vnstat,vnstat)
	@echo "[make] Initializing vnstat database for tailscale0..."
	@if ! $(run_as_root) vnstat --iflist | grep -q tailscale0; then \
		$(run_as_root) vnstat --add -i tailscale0; \
	fi
	@$(run_as_root) systemctl enable --now vnstat || true
	@echo "[make] vnstat installed and initialized for tailscale0"

remove-pkg-vnstat:
	$(call apt_remove,vnstat)

# nftables (kernel userspace tools)
.PHONY: install-pkg-nftables remove-pkg-nftables
install-pkg-nftables:
	@echo "📦 Installing nftables"
	$(call apt_install,nftables,nftables)
	@$(run_as_root) systemctl enable --now nftables || true
	@echo "✅ nftables installed and service enabled"

remove-pkg-nftables:
	$(call apt_remove,nftables)

# WireGuard (tools + kernel module helpers)
.PHONY: install-pkg-wireguard remove-pkg-wireguard
install-pkg-wireguard:
	@echo "📦 Installing WireGuard (tools + kernel modules)"
	$(call apt_install,wireguard,wireguard wireguard-tools)
	@echo "✅ WireGuard packages installed"

remove-pkg-wireguard:
	$(call apt_remove,wireguard wireguard-tools)

# Caddy (web server)
.PHONY: install-pkg-caddy remove-pkg-caddy
install-pkg-caddy:
	@echo "📦 Installing Caddy"
	$(call apt_install,caddy,caddy)
	@$(run_as_root) systemctl enable --now caddy || true
	@echo "✅ Caddy installed and enabled"

remove-pkg-caddy:
	$(call apt_remove,caddy)

# Unbound (DNS resolver)
.PHONY: install-pkg-unbound remove-pkg-unbound
install-pkg-unbound:
	@echo "📦 Installing Unbound"
	$(call apt_install,unbound,unbound)
	@$(run_as_root) systemctl enable --now unbound || true
	@echo "✅ Unbound installed and enabled"

remove-pkg-unbound:
	$(call apt_remove,unbound)

# ndppd (NDP proxy for IPv6 delegated prefixes)
.PHONY: install-pkg-ndppd remove-pkg-ndppd
install-pkg-ndppd:
	@echo "📦 Installing ndppd (NDP proxy)"
	$(call apt_install,ndppd,ndppd)
	@$(run_as_root) systemctl enable --now ndppd || true
	@echo "✅ ndppd installed and enabled"

remove-pkg-ndppd:
	$(call apt_remove,ndppd)


# checkmake (build from upstream Makefile)
CHECKMAKE_VERSION := 0.2.2
CHECKMAKE_BIN := /usr/local/bin/checkmake
STAMP_CHECKMAKE := $(STAMP_DIR)/checkmake.installed

install-pkg-checkmake: install-pkg-pandoc install-pkg-go
	@echo "[make] Installing checkmake (v$(CHECKMAKE_VERSION)) using upstream Makefile..."
	@if [ -x "$(CHECKMAKE_BIN)" ]; then \
	  INST_VER=$$($(CHECKMAKE_BIN) --version 2>/dev/null | awk '{print $$2}' || true); \
	  if [ "$$INST_VER" = "$(CHECKMAKE_VERSION)" ]; then \
		echo "[make] checkmake $(CHECKMAKE_VERSION) already installed; skipping build"; \
		exit 0; \
	  fi; \
	fi; \
	mkdir -p $(HOME)/src; \
	rm -rf $(HOME)/src/checkmake; \
	git clone --depth 1 --branch v$(CHECKMAKE_VERSION) https://github.com/mrtazz/checkmake.git $(HOME)/src/checkmake; \
	cd $(HOME)/src/checkmake && git config advice.detachedHead false && git checkout v$(CHECKMAKE_VERSION); \
	cd $(HOME)/src/checkmake && \
	BUILDER_NAME="$$(git config --get user.name)" \
	BUILDER_EMAIL="$$(git config --get user.email)" \
	make; \
	$(run_as_root) install -m 0755 $(HOME)/src/checkmake/checkmake $(CHECKMAKE_BIN); \
	echo "version=$(CHECKMAKE_VERSION) installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" | $(run_as_root) tee "$(STAMP_CHECKMAKE)" >/dev/null; \
	@echo "[make] Installed checkmake built by $$(git config --get user.name) <$$(git config --get user.email)>"; \
	@$(CHECKMAKE_BIN) --version

remove-pkg-checkmake:
	$(call remove_cmd,checkmake,rm -f /usr/local/bin/checkmake && rm -rf $(HOME)/src/checkmake && rm -f $(STAMP_CHECKMAKE))

# strace (used for debugging)
install-pkg-strace:
	$(call apt_install,strace,strace)

remove-pkg-strace:
	$(call apt_remove,strace)

# Headscale build (remote install fallback to upstream release)
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
		headscale version; \
	fi

# ---------------------------------------------------------------------
# Pinned upstream pandoc .deb install (safer, atomic, stamp file)
# see https://github.com/jgm/pandoc/releases
# ---------------------------------------------------------------------
PANDOC_VERSION := 3.8.2.1
PANDOC_DEB_URL := https://github.com/jgm/pandoc/releases/download/3.8.2.1/pandoc-3.8.2.1-1-amd64.deb
PANDOC_SHA256 := 5d4ecbf9c616360a9046e14685389ff2898088847e5fb260eedecd023453995a
PANDOC_DEB := /tmp/pandoc-$(PANDOC_VERSION)-amd64.deb
STAMP_PANDOC := $(STAMP_DIR)/pandoc.installed

.PHONY: install-pkg-pandoc upgrade-pkg-pandoc remove-pkg-pandoc

.SILENT: install-pkg-pandoc

install-pkg-pandoc:
	@sudo mkdir -p $(STAMP_DIR); \
	installed_bin=$$(command -v pandoc 2>/dev/null || true); \
	installed_version=$$(dpkg-query -W -f='$${Version}' pandoc 2>/dev/null || true); \
	installed_version_base=$${installed_version%%-*}; \
	if [ -n "$$installed_bin" ] && [ -f "$(PANDOC_DEB)" ] && \
	   [ "$$(sha256sum "$(PANDOC_DEB)" | cut -d' ' -f1)" = "$(PANDOC_SHA256)" ] && \
	   [ "$$installed_version_base" = "$(PANDOC_VERSION)" ]; then \
		echo "[make] pandoc $(PANDOC_VERSION) already installed and binary checksum matches; nothing to do"; \
		exit 0; \
	fi; \
	rm -f $(PANDOC_DEB); \
	set -euo pipefail; \
	trap 'rm -f "$(PANDOC_DEB)";' EXIT; \
	curl -fsSL "$(PANDOC_DEB_URL)" -o "$(PANDOC_DEB)"; \
	echo "$(PANDOC_SHA256)  $(PANDOC_DEB)" | sha256sum -c - >/dev/null; \
	#echo "[make] Checksum OK"; \
	DEBIAN_FRONTEND=noninteractive sudo dpkg -i "$(PANDOC_DEB)" >/dev/null 2>&1 || true; \
	DEBIAN_FRONTEND=noninteractive sudo apt-get -y -f install --no-install-recommends >/dev/null; \
	sudo apt-mark hold pandoc >/dev/null; \
	installed_version=$$(dpkg-query -W -f='$${Version}' pandoc 2>/dev/null || true); \
	installed_version_base=$${installed_version%%-*}; \
	#echo "[make] installed_version='$$installed_version' installed_version_base='$$installed_version_base'"; \
	if [ "$$installed_version_base" != "$(PANDOC_VERSION)" ]; then \
	  echo "[make] ERROR: pandoc not found or wrong version after install (installed=$$installed_version)"; rm -f "$(PANDOC_DEB)"; trap - EXIT; exit 1; \
	fi; \
	echo "version=$$installed_version sha256=$(PANDOC_SHA256) installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" | sudo tee "$(STAMP_PANDOC)" >/dev/null; \
	#rm -f "$(PANDOC_DEB)"; \
	trap - EXIT; \
	echo "[make] pandoc $(PANDOC_VERSION) installed and recorded in $(STAMP_PANDOC)"


upgrade-pkg-pandoc: $(STAMP_PANDOC)
	@echo "[make] Upgrading pandoc only if previously installed by Makefile..."
	@$(call apt_update_if_needed)
	@DEBIAN_FRONTEND=noninteractive sudo apt-get install --only-upgrade -y pandoc || true
	@tmp=$$(mktemp); dpkg-query -W -f='${Version}\n' pandoc > "$$tmp" 2>/dev/null || echo "unknown" > "$$tmp"; \
	echo "version=$$(cat $$tmp) upgraded_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" | sudo tee $(STAMP_PANDOC) >/dev/null; \
	rm -f "$$tmp"
	@echo "[make] pandoc upgrade complete; stamp updated"

remove-pkg-pandoc:
	@echo "[make] Requested removal of pandoc..."; \
	if dpkg -s pandoc >/dev/null 2>&1; then \
		echo "[make] pandoc is installed; removing..."; \
		DEBIAN_FRONTEND=noninteractive sudo apt-get remove -y --allow-change-held-packages -o Dpkg::Options::=--force-confold pandoc || echo "[make] apt-get remove returned non-zero"; \
		DEBIAN_FRONTEND=noninteractive sudo apt-get autoremove -y || true; \
		if [ -f "$(STAMP_PANDOC)" ]; then \
			sudo apt-mark unhold pandoc || true; \
			sudo rm -f "$(STAMP_PANDOC)"; \
			echo "[make] Removed stamp $(STAMP_PANDOC)"; \
			stampdir=$$(dirname "$(STAMP_PANDOC)"); \
			if [ -d "$$stampdir" ] && [ -z "$$(ls -A "$$stampdir")" ]; then \
				sudo rmdir "$$stampdir" 2>/dev/null && echo "[make] Removed empty stamp dir $$stampdir" || true; \
			fi; \
		else \
			echo "[make] Stamp $(STAMP_PANDOC) not present"; \
		fi; \
	else \
		echo "[make] pandoc not installed; nothing to do"; \
	fi

.PHONY: install-pkg-shellcheck remove-pkg-shellcheck \
		install-pkg-codespell remove-pkg-codespell \
		install-pkg-aspell remove-pkg-aspell

# ShellCheck (shell script linter)
install-pkg-shellcheck:
	@echo "📦 Installing shellcheck (shell script linter)"
	$(call apt_install,shellcheck,shellcheck)
	@echo "[make] shellcheck version: $$(shellcheck --version | head -n1)"

remove-pkg-shellcheck:
	$(call apt_remove,shellcheck)

# codespell (common typo finder)
install-pkg-codespell:
	@echo "📦 Installing codespell (typo finder)"
	$(call apt_install,codespell,codespell)
	@echo "[make] codespell version: $$(codespell --version 2>/dev/null || echo 'unknown')"

remove-pkg-codespell:
	$(call apt_remove,codespell)

# aspell (spell checker)
install-pkg-aspell:
	@echo "📦 Installing aspell (spell checker)"
	$(call apt_install,aspell,aspell)
	@echo "[make] aspell version: $$(aspell --version 2>/dev/null | head -n1 || echo 'unknown')"

remove-pkg-aspell:
	$(call apt_remove,aspell)

# xcaddy + custom Caddy build with rate_limit plugin
XCADDY_BIN := /usr/local/bin/xcaddy
CADDY_BIN  := /usr/bin/caddy
CADDY_BACKUP := /usr/bin/caddy.orig
CADDY_VERSION := v2.8.0
STAMP_CADDY := $(STAMP_DIR)/caddy.installed

# Map uname -m to Debian-style arch names
ARCH := $(shell dpkg --print-architecture)

.PHONY: install-pkg-xcaddy build-caddy-custom verify-caddy remove-pkg-xcaddy restore-caddy

install-pkg-xcaddy:
	@echo "📦 Installing xcaddy (builder for custom Caddy)"
	@if [ ! -x "$(XCADDY_BIN)" ]; then \
		curl -sSL https://github.com/caddyserver/xcaddy/releases/download/v0.4.5/xcaddy_0.4.5_linux_$(ARCH).tar.gz \
			-o /tmp/xcaddy.tar.gz; \
		sudo tar -xzf /tmp/xcaddy.tar.gz -C /usr/local/bin xcaddy; \
		rm -f /tmp/xcaddy.tar.gz; \
		echo "✅ xcaddy installed at $(XCADDY_BIN)"; \
	else \
		echo "ℹ️ xcaddy already present at $(XCADDY_BIN)"; \
	fi

build-caddy-custom: install-pkg-xcaddy
	@set -euo pipefail; \
	echo "🔨 Building Caddy $(CADDY_VERSION) with rate_limit plugin..."; \
	BUILD_DIR=$$(mktemp -d /tmp/caddy-build.XXXXXX); \
	trap 'rm -rf "$$BUILD_DIR"' EXIT; \
	cd "$$BUILD_DIR"; \
	"$(XCADDY_BIN)" build "$(CADDY_VERSION)" \
		--with github.com/mholt/caddy-ratelimit@v0.1.0; \
	echo "📦 Deploying custom Caddy binary"; \
	if [ -x "$(CADDY_BIN)" ] && [ ! -f "$(CADDY_BACKUP)" ]; then \
		sudo mv "$(CADDY_BIN)" "$(CADDY_BACKUP)"; \
		echo "💾 Original Caddy backed up to $(CADDY_BACKUP)"; \
	fi; \
	sudo install -m 0755 -o root -g root "$$BUILD_DIR/caddy" "$(CADDY_BIN)";

verify-caddy:
	echo "🔎 Verifying Caddy installation"; \
	if ! "$(CADDY_BIN)" version >/dev/null 2>&1; then \
		echo "❌ Installed Caddy not executable"; \
		[ -f "$(CADDY_BACKUP)" ] && sudo mv "$(CADDY_BACKUP)" "$(CADDY_BIN)"; \
		exit 1; \
	fi; \
	if ! "$(CADDY_BIN)" list-modules | grep -q '^http.handlers.rate_limit$$'; then \
		echo "❌ rate_limit plugin not found in installed binary"; \
		[ -f "$(CADDY_BACKUP)" ] && sudo mv "$(CADDY_BACKUP)" "$(CADDY_BIN)"; \
		exit 1; \
	fi; \
	VERSION=$$("$(CADDY_BIN)" version); \
	echo "✅ Caddy verified with rate_limit plugin: $$VERSION"; \
	echo "version=$$VERSION installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		| sudo tee "$(STAMP_CADDY)" >/dev/null


remove-pkg-xcaddy:
	@echo "🗑️ Removing xcaddy"
	@sudo rm -f $(XCADDY_BIN)
	@echo "✅ xcaddy removed"

restore-caddy:
	@echo "♻️ Restoring original Caddy binary"
	@if [ -f "$(CADDY_BACKUP)" ]; then \
		sudo mv $(CADDY_BACKUP) $(CADDY_BIN); \
		echo "✅ Original Caddy restored"; \
	else \
		echo "⚠️ No backup found at $(CADDY_BACKUP)"; \
	fi

# ============================================================
# code-server (browser-based VS Code)
# ============================================================

CODE_SERVER_BIN := /usr/bin/code-server
STAMP_CODE_SERVER := $(STAMP_DIR)/code-server.installed

.PHONY: install-pkg-code-server remove-pkg-code-server verify-pkg-code-server

install-pkg-code-server:
	@echo "📦 Installing code-server (VS Code in browser)"
	@if [ -x "$(CODE_SERVER_BIN)" ]; then \
		echo "[make] code-server already installed; skipping"; \
	else \
		echo "[make] Running official code-server installer"; \
		curl -fsSL https://code-server.dev/install.sh -o /tmp/code-server-install.sh; \
		$(run_as_root) bash /tmp/code-server-install.sh; \
		rm -f /tmp/code-server-install.sh; \
	fi
	@$(MAKE) verify-pkg-code-server
	@echo "version=$$($(CODE_SERVER_BIN) --version) installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		| $(run_as_root) tee "$(STAMP_CODE_SERVER)" >/dev/null
	@echo "✅ code-server installed"

verify-pkg-code-server:
	@echo "🔎 Verifying code-server installation"
	@if ! $(CODE_SERVER_BIN) --version >/dev/null 2>&1; then \
		echo "❌ code-server not functional"; exit 1; \
	else \
		echo "✔ code-server version: $$($(CODE_SERVER_BIN) --version)"; \
	fi

remove-pkg-code-server:
	@echo "🗑️ Removing code-server"
	@if dpkg -s code-server >/dev/null 2>&1; then \
		$(run_as_root) apt-get remove -y code-server; \
	fi
	@$(run_as_root) rm -f "$(STAMP_CODE_SERVER)" || true
	@echo "✅ code-server removed"
