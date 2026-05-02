# mk/20_deps.mk
# Package installation and build helpers

STAMP_DIR := $(STAMP_DIR_ROOT)
GO_MODERN_VERSION := 1.25.5
GO_MODERN_PREFIX  := /usr/local/go
GO_MODERN_BIN     := $(GO_MODERN_PREFIX)/bin/go
STAMP_GO_MODERN   := $(STAMP_DIR)/go-modern.installed
GO_ARCH           := amd64
GO_DIST_URL       := https://go.dev/dl/go$(GO_MODERN_VERSION).linux-$(GO_ARCH).tar.gz

# ------------------------------------------------------------
# REUSABLE MACROS
# ------------------------------------------------------------

# Macro: go_install_from_source
# Compiles a Go tool into a temp dir and uses IFC to install resulting binaries atomically
define go_install_from_source
	BIN_NAME="$(1)"; VERSION_STR="$(2)"; \
	REQ_VER="$${VERSION_STR##*@}"; \
	DEST="$(INSTALL_PATH)/$$BIN_NAME"; \
	STAMP="$(STAMP_DIR)/$$BIN_NAME.installed"; \
	if [ -f "$$STAMP" ] && [ -f "$$DEST" ]; then \
		CURRENT_SHA=$$(sha256sum "$$DEST" | awk '{print $$1}'); \
		STAMP_SHA=$$(grep -oP 'sha256=\K[a-f0-9]+' "$$STAMP" || echo "none"); \
		if [ "$$CURRENT_SHA" = "$$STAMP_SHA" ]; then \
			echo "✅ $$BIN_NAME $$REQ_VER already installed (hash match)"; \
			exit 0; \
		fi; \
	fi; \
	echo "📦 Building $$BIN_NAME from source ($$VERSION_STR)..."; \
	TMP_BIN=$$(mktemp -d /tmp/go-build.XXXXXX); \
	GOBIN=$$TMP_BIN $(GO_MODERN_BIN) install $$VERSION_STR || exit 1; \
	for f in $$TMP_BIN/*; do \
		FILENAME=$$(basename $$f); \
		TARGET="$(INSTALL_PATH)/$$FILENAME"; \
		echo "🚚 Installing $$FILENAME via IFC"; \
		RC=0; \
		$(run_as_root) $(INSTALL_FILE_IF_CHANGED) -q "" "" "$$f" "" "" "$$TARGET" "$(ROOT_UID)" "$(ROOT_GID)" "0755" || RC=$$?; \
		if [ "$$RC" -ne 0 ] && [ "$$RC" -ne 3 ]; then \
			echo "❌ IFC failed for $$TARGET (exit $$RC)"; \
			exit $$RC; \
		fi; \
	done; \
	NEW_SHA=$$(sha256sum "$$DEST" | awk '{print $$1}'); \
	TMP_STAMP=$$(mktemp); \
	echo "version=$$REQ_VER sha256=$$NEW_SHA installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$$TMP_STAMP"; \
	$(run_as_root) install -m 0644 "$$TMP_STAMP" "$$STAMP"; \
	rm -f "$$TMP_STAMP"; \
	rm -rf "$$TMP_BIN"
endef

# Removes only regular files or symlinks.
# Arguments:
#   $(1) List of paths to remove
#   $(2) Optional package name (e.g., "age", "go"). Used in error messages.
#        If empty, the function uses the first path's basename in the error message.
#
# Behavior:
#   1. If path does not exist: Silently skips (idempotent).
#   2. If path is a directory: Fails loudly.
#   3. If path is unknown type: Fails loudly.
#   4. If path is file/symlink: Removes it.
define remove_file_or_link_if_exists
	sh -c '\
		DISPLAY_NAME="$(if $(1),$(shell basename "$(firstword $(1))"),files)"; \
		[ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ] && \
			echo "ℹ️ Cleaning up $$DISPLAY_NAME"; \
		for item in $(1); do \
			[ -z "$$item" ] && continue; \
			LABEL="$(if $(2),$(2),$$item)"; \
			if [ ! -e "$$item" ]; then \
				[ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ] && \
					echo "ℹ️ Skipping (not found): $$item"; \
				continue; \
			fi; \
			if [ -d "$$item" ]; then \
				echo "❌ ERROR: '\''$$LABEL'\'' is a directory. Refusing to delete directories." >&2; \
				exit 1; \
			fi; \
			if [ -L "$$item" ] || [ -f "$$item" ]; then \
				[ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ] && \
					echo "🗑️ Removing: $$item"; \
				$(run_as_root) rm -f "$$item"; \
				continue; \
			fi; \
			echo "❌ ERROR: '\''$$LABEL'\'' is an unsupported type (not a file or symlink)." >&2; \
			exit 1; \
		done; \
		[ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ] && \
			echo "ℹ️ $$(echo "$$DISPLAY_NAME" | awk '\''{print toupper(substr($$0,1,1)) substr($$0,2)}'\'') removed"; \
		exit 0; \
	'
endef

# ------------------------------------------------------------
# TAR/GZIP PACKAGE HELPERS (Reusable across Go, Kopia, Pandoc…)
# ------------------------------------------------------------

# $(call fetch_tarball,URL,TARBALL_PATH)
define fetch_tarball
	RET=0; \
	OUT="$$( $(run_as_root) "$(INSTALL_URL_FILE_IF_CHANGED)" \
		"$(1)" "$(2)" "$(ROOT_UID)" "$(ROOT_GID)" "0644" 2>&1 )" || RET=$$?; \
	echo $$RET
endef

# $(call extract_tarball,TARBALL,DESTDIR)
define extract_tarball
	$(run_as_root) sh -e -c '\
		TMPDIR="$$(mktemp -d /tmp/extract.XXXXXX)"; \
		rm -rf "$(2)"; \
		tar -C "$$TMPDIR" -xzf "$(1)"; \
		mv "$$TMPDIR"/* "$(2)"; \
		rm -rf "$$TMPDIR"; \
	'
endef


# $(call install_symlink,TARGET,LINK)
define install_symlink
	$(run_as_root) ln -sf "$(1)" "$(2)"
endef

.PHONY: deps install-pkg-go remove-pkg-go \
	install-pkg-pandoc upgrade-pkg-pandoc remove-pkg-pandoc \
	install-pkg-checkmake remove-pkg-checkmake \
	install-pkg-strace remove-pkg-strace \
	install-pkg-vnstat remove-pkg-vnstat \
	install-pkg-tailscale upgrade-pkg-tailscale remove-pkg-tailscale \
	install-pkg-age remove-pkg-age \
	install-pkg-rclone remove-pkg-rclone \
	install-pkg-kopia remove-pkg-kopia \
	headscale-build

# ------------------------------------------------------------
# Aggregate deps target
# ------------------------------------------------------------
deps: \
	install-pkg-go install-pkg-pandoc install-pkg-checkmake \
	install-pkg-strace install-pkg-vnstat \
	install-pkg-age install-pkg-rclone install-pkg-kopia \
	install-pkg-sops | prereqs

# ------------------------------------------------------------
# Tailscale repository
# ------------------------------------------------------------
DEBIAN_CODENAME ?= bookworm
TS_REPO_KEYRING := /usr/share/keyrings/tailscale-archive-keyring.gpg
TS_REPO_LIST    := /etc/apt/sources.list.d/tailscale.list

.PHONY: tailscale-repo install-pkg-tailscale upgrade-pkg-tailscale remove-pkg-tailscale verify-pkg-tailscale

tailscale-repo: | ensure-run-as-root ensure-default-gateway
	@echo "📦 Adding Tailscale apt repository (Debian $(DEBIAN_CODENAME))"
	@$(run_as_root) install -d -m 0755 /usr/share/keyrings
	@curl -fsSL https://pkgs.tailscale.com/stable/debian/$(DEBIAN_CODENAME).noarmor.gpg \
	| $(run_as_root) install -m 0644 -o root -g root /dev/stdin $(TS_REPO_KEYRING)
	@curl -fsSL https://pkgs.tailscale.com/stable/debian/$(DEBIAN_CODENAME).list \
	| $(run_as_root) install -m 0644 -o root -g root /dev/stdin $(TS_REPO_LIST)
	@$(call apt_update_if_needed)
	@echo "✅ Tailscale repository configured"

install-pkg-tailscale: tailscale-repo verify-pkg-tailscale | ensure-run-as-root ensure-default-gateway
	@echo "📦 Installing Tailscale (client + daemon)"
	@$(call apt_install_group,tailscale)
	@$(call ensure_service_enabled,tailscaled,tailscaled)
	@echo "✅ Tailscale installed and running"

upgrade-pkg-tailscale: tailscale-repo verify-pkg-tailscale | ensure-run-as-root ensure-default-gateway
	@echo "⬆️ Upgrading Tailscale to latest stable"
	@$(call apt_update_if_needed)
	@$(run_as_root) DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y tailscale
	@$(run_as_root) systemctl restart tailscaled >/dev/null 2>&1
	@echo "✅ Tailscale upgraded"

remove-pkg-tailscale: | ensure-run-as-root
	@if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "🗑️ Removing Tailscale"; \
	fi
	@$(run_as_root) sh -c '\
		systemctl stop tailscaled >/dev/null 2>&1 || true; \
		systemctl disable tailscaled >/dev/null 2>&1 || true; \
	'
	@{ $(call apt_remove,tailscale) ; }
	@if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "✅ Tailscale removed"; \
	fi

verify-pkg-tailscale: | ensure-run-as-root ensure-default-gateway
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

GO_TARBALL := $(STAMP_DIR)/go$(GO_MODERN_VERSION).linux-$(GO_ARCH).tar.gz

install-pkg-go: | ensure-run-as-root ensure-default-gateway ensure-stamp-dir
	@set -e; \
	if dpkg -s golang-go >/dev/null 2>&1 || dpkg -s golang-1.19-go >/dev/null 2>&1; then \
		echo "🗑️ Removing legacy apt Go version..."; \
		$(run_as_root) apt-get purge -y golang-go golang-1.19-go >/dev/null 2>&1; \
		$(run_as_root) apt-get autoremove -y >/dev/null 2>&1; \
	fi; \
	echo "🔍 Checking for updates: $(GO_DIST_URL)"; \
	RET="$$( \
		$(call fetch_tarball,$(GO_DIST_URL),$(GO_TARBALL)) \
	)"; \
	if [ ! -x "$(GO_MODERN_BIN)" ] || [ "$$RET" -eq "$(INSTALL_IF_CHANGED_EXIT_CHANGED)" ]; then \
		echo "📦 Extracting Go $(GO_MODERN_VERSION)..."; \
		$(call extract_tarball,$(GO_TARBALL),$(GO_MODERN_PREFIX)); \
		echo "🔗 Installing symlink"; \
		$(call install_symlink,$(GO_MODERN_BIN),/usr/local/bin/go); \
		echo "✅ $$("$(GO_MODERN_BIN)" version) is active"; \
	else \
		echo "✅ Go $(GO_MODERN_VERSION) already installed at $(GO_MODERN_PREFIX)"; \
	fi

remove-pkg-go: | ensure-run-as-root
	@$(call remove_file_or_link_if_exists,$(GO_MODERN_BIN) /usr/local/bin/go,go)

# ------------------------------------------------------------
# vnstat
# ------------------------------------------------------------
install-pkg-vnstat: install-pkg-core-apt | ensure-run-as-root ensure-default-gateway
	@if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "ℹ️ vnstat already ensured by core apt group"; \
	fi
	@if ! vnstat --iflist | grep -q tailscale0; then \
		echo "Initializing vnstat database for tailscale0..."; \
		$(run_as_root) vnstat --add -i tailscale0; \
	fi
	@{ $(call ensure_service_enabled,vnstat,vnstat) }
	@echo "✅ vnstat installed and initialized for tailscale0"

remove-pkg-vnstat:
	@{ $(call apt_remove,vnstat) ; }

# ------------------------------------------------------------
# nftables
# ------------------------------------------------------------
install-pkg-nftables: install-pkg-core-apt | ensure-run-as-root ensure-default-gateway
	@if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "ℹ️ nftables already ensured by core apt group"; \
	fi
	@{ $(call ensure_service_enabled,nftables,nftables) }

remove-pkg-nftables:
	@{ $(call apt_remove,nftables) ; }

# ------------------------------------------------------------
# WireGuard
# ------------------------------------------------------------
install-pkg-wireguard: install-pkg-core-apt | ensure-run-as-root ensure-default-gateway
	@if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "ℹ️ WireGuard already ensured by core apt group"; \
	fi

remove-pkg-wireguard:
	@{ $(call apt_remove,wireguard wireguard-tools) ; }

# ------------------------------------------------------------
# Caddy
# ------------------------------------------------------------
install-pkg-caddy: install-pkg-core-apt | ensure-run-as-root ensure-default-gateway
	@if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "ℹ️ Caddy already ensured by core apt group"; \
	fi

remove-pkg-caddy:
	@{ $(call apt_remove,caddy) ; }
	@$(run_as_root) rm -f /etc/caddy/Caddyfile

# ------------------------------------------------------------
# Age (Source build via Go)
# ------------------------------------------------------------
AGE_BIN        := /usr/local/bin/age
AGE_KEYGEN_BIN := /usr/local/bin/age-keygen
AGE_VERSION    := v1.2.1

install-pkg-age: install-pkg-go | ensure-default-gateway ensure-stamp-dir
	@if [ -x "$(AGE_BIN)" ] && $(AGE_BIN) --version 2>&1 | grep -q "$(AGE_VERSION)"; then \
		echo "✅ age $(AGE_VERSION) already installed at $(AGE_BIN)"; \
	else \
		echo "📦 Building age $(AGE_VERSION) from source..."; \
		$(call go_install_from_source,age,filippo.io/age/cmd/...@$(AGE_VERSION)); \
		echo "✅ age $(AGE_VERSION) installed"; \
	fi

remove-pkg-age:
	@$(call remove_file_or_link_if_exists,$(AGE_BIN) $(AGE_KEYGEN_BIN),age)

# ------------------------------------------------------------
# SOPS (Secrets Operations - Source build via Go)
# ------------------------------------------------------------
SOPS_VERSION := v3.9.4

.PHONY: install-pkg-sops remove-pkg-sops

install-pkg-sops: install-pkg-go | ensure-default-gateway ensure-stamp-dir
	@if command -v sops >/dev/null 2>&1; then \
		echo "✅ SOPS already installed: $$(sops --version | head -n1)"; \
	else \
		echo "📦 Building SOPS $(SOPS_VERSION) from source..."; \
		$(call go_install_from_source,sops,github.com/getsops/sops/v3/cmd/sops@$(SOPS_VERSION)); \
		echo "✅ SOPS $(SOPS_VERSION) installed"; \
	fi

remove-pkg-sops:
	@$(call remove_file_or_link_if_exists,$(INSTALL_PATH)/sops,SOPS binary)

# ------------------------------------------------------------
# Rclone (The Swiss Army Knife for Cloud Storage)
# ------------------------------------------------------------
install-pkg-rclone: install-pkg-core-apt | ensure-run-as-root ensure-default-gateway
	@if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "ℹ️ rclone already ensured by core apt group"; \
	fi

remove-pkg-rclone:
	@{ $(call apt_remove,rclone) ; }

# ------------------------------------------------------------
# Kopia (GitHub tarball via centralized installer)
# ------------------------------------------------------------

KOPIA_VERSION := 0.16.0
KOPIA_URL := https://github.com/kopia/kopia/releases/download/v$(KOPIA_VERSION)/kopia-$(KOPIA_VERSION)-linux-x64.tar.gz
KOPIA_STAMP := $(STAMP_DIR)/kopia.installed

.PHONY: install-pkg-kopia
install-pkg-kopia: ensure-run-as-root ensure-default-gateway ensure-stamp-dir install-all
	@echo "📦 Ensuring Kopia $(KOPIA_VERSION)"
	@$(run_as_root) $(INSTALL_PATH)/install_github_asset.sh \
		"$(KOPIA_URL)" \
		"$(INSTALL_PATH)/kopia" \
		"$(KOPIA_SHA256)" \
		"$(KOPIA_STAMP)"

.PHONY: remove-pkg-kopia
remove-pkg-kopia: | ensure-run-as-root
	@$(call remove_file_or_link_if_exists,/usr/local/bin/kopia $(KOPIA_STAMP),kopia) || true
	@$(run_as_root) rm -rf /usr/local/kopia >/dev/null 2>&1 || true


# ------------------------------------------------------------
# ndppd
# ------------------------------------------------------------
enable-ndppd: | ensure-run-as-root
	@if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "📦 Enabling ndppd service"; \
	fi
	@{ $(call ensure_service_enabled,ndppd,ndppd) }

# ------------------------------------------------------------
# checkmake
# ------------------------------------------------------------
CHECKMAKE_VERSION := 0.2.2
CHECKMAKE_BIN     := /usr/local/bin/checkmake
CHECKMAKE_SRC     := $(HOME)/src/checkmake
STAMP_CHECKMAKE   := $(STAMP_DIR)/checkmake.installed

ensure-git-detachedhead-silenced:
	@git config --global advice.detachedHead false || true

install-pkg-checkmake: ensure-run-as-root install-pkg-pandoc install-pkg-go ensure-git-detachedhead-silenced | ensure-default-gateway ensure-stamp-dir
	@echo "📦 Checking checkmake (v$(CHECKMAKE_VERSION))"

	# Fast path: skip everything if already installed
	@if [ -f "$(STAMP_CHECKMAKE)" ] && [ -f "$(CHECKMAKE_BIN)" ]; then \
		CURRENT_SHA=$$(sha256sum "$(CHECKMAKE_BIN)" | awk '{print $$1}'); \
		STAMP_SHA=$$(grep -oP 'sha256=\K[a-f0-9]+' "$(STAMP_CHECKMAKE)" || echo none); \
		if [ "$$CURRENT_SHA" = "$$STAMP_SHA" ]; then \
			echo "✅ checkmake v$(CHECKMAKE_VERSION) already installed (hash match)"; \
			exit 0; \
		fi; \
	fi

	@{ \
		set -e; \
		mkdir -p "$(CHECKMAKE_SRC)"; \
		if [ -d "$(CHECKMAKE_SRC)/.git" ]; then \
			cd "$(CHECKMAKE_SRC)"; \
			if ! git fetch --tags --quiet || ! git checkout --quiet "v$(CHECKMAKE_VERSION)" 2>/dev/null; then \
				cd ..; \
				rm -rf "$(CHECKMAKE_SRC)"; \
				git clone --quiet --depth 1 --branch "v$(CHECKMAKE_VERSION)" https://github.com/mrtazz/checkmake.git "$(CHECKMAKE_SRC)"; \
			fi; \
		else \
			git clone --quiet --depth 1 --branch "v$(CHECKMAKE_VERSION)" https://github.com/mrtazz/checkmake.git "$(CHECKMAKE_SRC)"; \
		fi; \
	}

	@{ \
		cd "$(CHECKMAKE_SRC)"; \
		$(call go_install_from_source,checkmake,github.com/mrtazz/checkmake/cmd/checkmake@v$(CHECKMAKE_VERSION)); \
	}


remove-pkg-checkmake: | ensure-run-as-root
	@{ \
		$(call remove_file_or_link_if_exists,$(CHECKMAKE_BIN) $(STAMP_CHECKMAKE),checkmake); \
		$(run_as_root) rm -rf "$(CHECKMAKE_SRC)" || true; \
	}

# ------------------------------------------------------------
# strace
# ------------------------------------------------------------
install-pkg-strace: install-pkg-core-apt | ensure-run-as-root ensure-default-gateway
	@if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "ℹ️ strace already ensured by core apt group"; \
	fi

remove-pkg-strace:
	@{ $(call apt_remove,strace) ; }

# ------------------------------------------------------------
# Headscale
# ------------------------------------------------------------
HEADSCALE_VERSION ?= v0.27.1

headscale-build: install-pkg-go | ensure-default-gateway ensure-stamp-dir
	@if command -v headscale >/dev/null 2>&1; then \
		CURRENT_VER=$$(headscale version | awk '{print $$3}'); \
		if [ "$$CURRENT_VER" = "$(HEADSCALE_VERSION)" ]; then \
			echo "✅ headscale $(HEADSCALE_VERSION) already installed (hash match)"; \
			exit 0; \
		fi; \
	fi
	@$(call go_install_from_source,headscale,github.com/juanfont/headscale/cmd/headscale@$(HEADSCALE_VERSION))
	@echo "✅ headscale $(HEADSCALE_VERSION) installed"

remove-pkg-headscale: | ensure-run-as-root
	@$(call remove_file_or_link_if_exists,$(INSTALL_PATH)/headscale $(STAMP_DIR)/headscale.installed,headscale)

# ------------------------------------------------------------
# Pandoc (pinned .deb)
# ------------------------------------------------------------
PANDOC_VERSION := 3.9.0.2
PANDOC_DEB_URL := https://github.com/jgm/pandoc/releases/download/3.9.0.2/pandoc-3.9.0.2-1-amd64.deb
PANDOC_SHA256  := ce4ac48f48aa7eadc1f5dbdf3449a1739f188ecb8c5421c5adc070fe7479e567

STAMP_PANDOC := $(STAMP_DIR)/pandoc.installed

.SILENT: install-pkg-pandoc
.PHONY: install-pkg-pandoc
install-pkg-pandoc: ensure-run-as-root ensure-default-gateway ensure-stamp-dir install-all
	@echo "📦 Ensuring Pandoc $(PANDOC_VERSION)"
	@$(run_as_root) $(INSTALL_PATH)/install_github_asset.sh \
		"$(PANDOC_DEB_URL)" \
		"$(INSTALL_PATH)/pandoc" \
		"$(PANDOC_SHA256)" \
		"$(STAMP_PANDOC)"

upgrade-pkg-pandoc: $(STAMP_PANDOC) | ensure-run-as-root ensure-default-gateway
	@echo "⬆️ Upgrading pandoc..."
	@$(call apt_update_if_needed)
	@$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y pandoc || true
	@tmp=$$(mktemp); dpkg-query -W -f='${Version}\n' pandoc > "$$tmp" 2>/dev/null || echo "unknown" > "$$tmp"; \
	echo "version=$$(cat $$tmp) upgraded_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		| $(run_as_root) tee $(STAMP_PANDOC) >/dev/null; \
	rm -f "$$tmp"
	@echo "✅ pandoc upgrade complete"

remove-pkg-pandoc: | ensure-run-as-root
	@if dpkg -s pandoc >/dev/null 2>&1; then \
		echo "🗑️ Removing pandoc (takes about 4 seconds)..."; \
		$(run_as_root) apt-get remove -y --allow-change-held-packages pandoc >/dev/null 2>&1; \
	fi

print-STAMP-KOPIA:
	@echo "STAMP_DIR_ROOT='$(STAMP_DIR_ROOT)'"
	@echo "STAMP_DIR='$(STAMP_DIR)'"
	@echo "STAMP_KOPIA='$(STAMP_KOPIA)'"

print-run-as-root:
	@printf 'run_as_root="%s"\n' "$(run_as_root)"
