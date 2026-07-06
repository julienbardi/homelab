# mk/20_deps.mk

# --------------------------------------------------------------------
# Package installation and build helpers
# --------------------------------------------------------------------
STAMP_DNS_OK := $(STAMP_DIR_ROOT)/dns-ok.stamp
STAMP_TS_OK  := $(STAMP_DIR_ROOT)/tailscale-hygiene.stamp
STAMP_CARGO_OK := $(STAMP_DIR_ROOT)/cargo-ok.stamp
STAMP_WATCHDOG_OK := $(STAMP_DIR_ROOT)/watchdog-ok.stamp
STAMP_VNSTAT_OK := $(STAMP_DIR_ROOT)/vnstat-ok.stamp
PROBES_STAMP := $(STAMP_DIR_ROOT)/deps-probes.checked
STAMP_GO_TARBALL := $(STAMP_DIR_ROOT)/go-tarball.checked
STAMP_PREREQS_OK := $(STAMP_DIR_ROOT)/prereqs-ok.stamp

# Stamp directory order-only dependencies (root scope)
$(STAMP_DNS_OK):            | $(STAMP_DIR_ROOT)
$(STAMP_TS_OK):             | $(STAMP_DIR_ROOT)
$(STAMP_CARGO_OK):          | $(STAMP_DIR_ROOT)
$(STAMP_WATCHDOG_OK):       | $(STAMP_DIR_ROOT)
$(STAMP_VNSTAT_OK):         | $(STAMP_DIR_ROOT)
$(PROBES_STAMP):            | $(STAMP_DIR_ROOT)
$(STAMP_GO_TARBALL):        | $(STAMP_DIR_ROOT)
$(STAMP_PREREQS_OK):        | $(STAMP_DIR_ROOT)

GO_MODERN_VERSION := 1.25.5
GO_MODERN_PREFIX  := /usr/local/go
GO_MODERN_BIN     := $(GO_MODERN_PREFIX)/bin/go
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
	STAMP="$(STAMP_DIR_ROOT)/$$BIN_NAME.installed"; \
	if [ -f "$$STAMP" ] && [ -f "$$DEST" ]; then \
		CURRENT_SHA=$$(sha256sum "$$DEST" | awk '{print $$1}'); \
		STAMP_SHA=$$(grep -oP 'sha256=\K[a-f0-9]+' "$$STAMP" || echo "none"); \
		if [ "$$CURRENT_SHA" = "$$STAMP_SHA" ]; then \
			echo "✅ $$BIN_NAME $$REQ_VER already installed (hash match)"; \
			exit 0; \
		fi; \
	fi; \
	echo "📦 Building $$BIN_NAME from source ($$VERSION_STR)..."; \
	TMP_BIN=$$(mktemp -p /dev/shm -d homelab.XXXXXX); \
	GOBIN=$$TMP_BIN $(GO_MODERN_BIN) install $$VERSION_STR || exit 1; \
	for f in $$TMP_BIN/*; do \
		FILENAME=$$(basename $$f); \
		TARGET="$(INSTALL_PATH)/$$FILENAME"; \
		echo "📦 Installing $$FILENAME via IFC"; \
		RC=0; \
		$(run_as_root) $(INSTALL_FILE_IF_CHANGED) -q "" "" "$$f" "" "" "$$TARGET" "$(ROOT_UID)" "$(ROOT_GID)" "0755" || RC=$$?; \
		if [ "$$RC" -ne 0 ] && [ "$$RC" -ne "$(INSTALL_IF_CHANGED_EXIT_CHANGED)" ]; then \
			echo "❌ IFC failed for $$TARGET (exit $$RC)"; \
			exit $$RC; \
		fi; \
	done; \
	NEW_SHA=$$(sha256sum "$$DEST" | awk '{print $$1}'); \
	TMP_STAMP=$$(mktemp); \
	echo "version=$$REQ_VER sha256=$$NEW_SHA installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$$TMP_STAMP"; \
	$(run_as_root) install -m 0644 "$$TMP_STAMP" "$$STAMP"; \
	$(run_as_root) rm -f "$$TMP_STAMP"; \
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
		TMPDIR=$$(mktemp -p /run -d homelab.XXXXXX); \
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


.PHONY: deps remove-pkg-go \
	upgrade-pkg-pandoc remove-pkg-pandoc \
	remove-pkg-checkmake \
	remove-pkg-strace \
	install-pkg-vnstat remove-pkg-vnstat \
	install-pkg-tailscale upgrade-pkg-tailscale remove-pkg-tailscale \
	remove-pkg-age \
	remove-pkg-rclone \
	remove-pkg-kopia \
	headscale-build

STAMP_INSTALLERS_OK := $(STAMP_DIR_ROOT)/installers-ok.stamp

$(STAMP_INSTALLERS_OK): \
	install-pkg-go \
	install-pkg-pandoc \
	install-pkg-checkmake \
	install-pkg-strace \
	install-pkg-age \
	install-pkg-rclone \
	install-pkg-kopia \
	install-pkg-sops \
	| $(STAMP_DIR_ROOT)
	@echo "ok" | $(run_as_root) tee "$@" >/dev/null

.PHONY: installers-ok
installers-ok: $(STAMP_INSTALLERS_OK)

# ------------------------------------------------------------
# Aggregate deps target
# ------------------------------------------------------------
STAMP_DEPS_OK := $(STAMP_DIR_ROOT)/deps-ok.stamp

$(STAMP_DEPS_OK): \
	dns-ok tailscale-hygiene-ok cargo-ok watchdog-ok vnstat-ok prereqs-ok \
	installers-ok \
	| $(STAMP_DIR_ROOT)
	@echo "ok" | $(run_as_root) tee "$@" >/dev/null
	@echo "✅ deps-ok complete"

.PHONY: deps-ok
deps-ok: $(STAMP_DEPS_OK)

.PHONY: deps
deps: deps-ok

# ------------------------------------------------------------
# Tailscale repository
# ------------------------------------------------------------
DEBIAN_CODENAME ?= bookworm
TS_REPO_KEYRING := /usr/share/keyrings/tailscale-archive-keyring.gpg
TS_REPO_LIST    := /etc/apt/sources.list.d/tailscale.list

.PHONY: tailscale-repo install-pkg-tailscale upgrade-pkg-tailscale remove-pkg-tailscale verify-pkg-tailscale

tailscale-repo: ensure-host-default-route
	@echo "📦 Adding Tailscale apt repository (Debian $(DEBIAN_CODENAME))"
	@$(run_as_root) install -d -m 0755 /usr/share/keyrings
	@curl -fsSL https://pkgs.tailscale.com/stable/debian/$(DEBIAN_CODENAME).noarmor.gpg \
	| $(run_as_root) install -m 0644 -o root -g root /dev/stdin $(TS_REPO_KEYRING)
	@curl -fsSL https://pkgs.tailscale.com/stable/debian/$(DEBIAN_CODENAME).list \
	| $(run_as_root) install -m 0644 -o root -g root /dev/stdin $(TS_REPO_LIST)
	@$(call apt_update_if_needed)
	@echo "✅ Tailscale repository configured"

install-pkg-tailscale: tailscale-repo verify-pkg-tailscale ensure-host-default-route
	@echo "📦 Installing Tailscale (client + daemon)"
	@$(call apt_install_group,tailscale)
	@$(call ensure_service_enabled,tailscaled,tailscaled)
	@echo "✅ Tailscale installed and running"

upgrade-pkg-tailscale: tailscale-repo verify-pkg-tailscale ensure-host-default-route
	@echo "⬆️ Upgrading Tailscale to latest stable"
	@$(call apt_update_if_needed)
	@$(run_as_root) DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y tailscale
	@$(run_as_root) systemctl restart tailscaled >/dev/null 2>&1
	@echo "✅ Tailscale upgraded"

remove-pkg-tailscale:
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

verify-pkg-tailscale: ensure-host-default-route
	@echo "🔍 Verifying Tailscale installation"
	@bash -c 'set -e; \
	CLI_VER=$$(tailscale version | head -n1); \
	DS_VER=$$($(run_as_root) tailscaled --version | head -n1); \
	echo "CLI: $$CLI_VER"; echo "DAEMON: $$DS_VER"; \
	if [ "$${CLI_VER}" != "$${DS_VER}" ]; then \
		echo "❌ Version mismatch"; exit 1; \
	fi; \
	echo "✅ Versions aligned" \
	'

# ------------------------------------------------------------
# Go (Modern Binary Distribution)
# ------------------------------------------------------------

GO_TARBALL := $(STAMP_DIR_ROOT)/go$(GO_MODERN_VERSION).linux-$(GO_ARCH).tar.gz
$(GO_TARBALL): | $(STAMP_DIR_ROOT)

install-pkg-go: | $(GO_TARBALL)
	@set -e; \
	# deps-probes handles legacy Go detection
	if [ -f "$(STAMP_DIR_ROOT)/legacy-go.detected" ]; then \
		echo "🗑️ Removing legacy apt Go version..."; \
		$(run_as_root) apt-get purge -y golang-go golang-1.19-go >/dev/null 2>&1; \
		$(run_as_root) apt-get autoremove -y >/dev/null 2>&1; \
	fi; \
	RET="$$( \
		$(call fetch_tarball,$(GO_DIST_URL),$(GO_TARBALL)) \
	)"
	if [ ! -x "$(GO_MODERN_BIN)" ] || [ "$$RET" -eq "$(INSTALL_IF_CHANGED_EXIT_CHANGED)" ]; then \
		echo "📦 Extracting Go $(GO_MODERN_VERSION)..."; \
		$(call extract_tarball,$(GO_TARBALL),$(GO_MODERN_PREFIX)); \
		echo "🔗 Installing symlink"; \
		$(call install_symlink,$(GO_MODERN_BIN),/usr/local/bin/go); \
		echo "✅ $$("$(GO_MODERN_BIN)" version) is active"; \
	else \
		echo "✅ Go $(GO_MODERN_VERSION) already installed at $(GO_MODERN_PREFIX)"; \
	fi

.PHONY: remove-pkg-go
remove-pkg-go:
	@$(call remove_file_or_link_if_exists,$(GO_MODERN_BIN) /usr/local/bin/go,go)

# ------------------------------------------------------------
# vnstat
# ------------------------------------------------------------
install-pkg-vnstat: prereqs-ok ensure-host-default-route
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
install-pkg-nftables: prereqs-ok ensure-host-default-route
	@if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "ℹ️ nftables already ensured by core apt group"; \
	fi
	@{ $(call ensure_service_enabled,nftables,nftables) }

remove-pkg-nftables:
	@{ $(call apt_remove,nftables) ; }

# ------------------------------------------------------------
# WireGuard
# ------------------------------------------------------------
install-pkg-wireguard: prereqs-ok ensure-host-default-route
	@if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "ℹ️ WireGuard already ensured by core apt group"; \
	fi

remove-pkg-wireguard:
	@{ $(call apt_remove,wireguard wireguard-tools) ; }

# ------------------------------------------------------------
# Caddy
# ------------------------------------------------------------
install-pkg-caddy: prereqs-ok ensure-host-default-route
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

install-pkg-age: install-pkg-go | $(STAMP_DIR_ROOT)
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
SOPS_VERSION := v3.13.1
STAMP_SOPS   := $(STAMP_DIR_ROOT)/sops.installed
$(STAMP_SOPS): | $(STAMP_DIR_ROOT)

install-pkg-sops: install-pkg-go | $(STAMP_DIR_ROOT)
	@echo "📦 Ensuring SOPS $(SOPS_VERSION)"

	# Fast path: skip if stamp + binary hash match
	@if [ -f "$(STAMP_SOPS)" ] && [ -x "$(SOPS_BIN)" ]; then \
		CURRENT_SHA=$$(sha256sum "$(SOPS_BIN)" | awk '{print $$1}'); \
		STAMP_SHA=$$(grep -oP 'sha256=\K[a-f0-9]+' "$(STAMP_SOPS)" || echo none); \
		if [ "$$CURRENT_SHA" = "$$STAMP_SHA" ]; then \
			echo "✅ SOPS $(SOPS_VERSION) already installed (hash match)"; \
			exit 0; \
		fi; \
	fi

	# Build from source
	@echo "📦 Building SOPS $(SOPS_VERSION) from source..."
	@$(call go_install_from_source,sops,github.com/getsops/sops/v3/cmd/sops@$(SOPS_VERSION))

	# Update stamp
	@NEW_SHA=$$(sha256sum "$(SOPS_BIN)" | awk '{print $$1}'); \
		echo "version=$(SOPS_VERSION) sha256=$$NEW_SHA installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
			| $(run_as_root) tee "$(STAMP_SOPS)" >/dev/null

	@echo "✅ SOPS $(SOPS_VERSION) installed"

.PHONY: remove-pkg-sops
remove-pkg-sops:
	@$(call remove_file_or_link_if_exists,$(SOPS_BIN) $(STAMP_SOPS),sops)

# ------------------------------------------------------------
# Rclone (The Swiss Army Knife for Cloud Storage)
# ------------------------------------------------------------
install-pkg-rclone:
	@if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "ℹ️ rclone already ensured by core apt group"; \
	fi

remove-pkg-rclone:
	@{ $(call apt_remove,rclone) ; }

# ------------------------------------------------------------
# Kopia (GitHub tarball via centralized installer)
# ------------------------------------------------------------

KOPIA_VERSION := 0.23.1
KOPIA_URL := https://github.com/kopia/kopia/releases/download/v$(KOPIA_VERSION)/kopia-$(KOPIA_VERSION)-linux-x64.tar.gz
KOPIA_SHA256 := e306c3d48b47756912928738241baffe68d1a8a16ab804ab3fbabd725a61df7f
KOPIA_STAMP := $(STAMP_DIR_ROOT)/kopia.installed
$(KOPIA_STAMP): | $(STAMP_DIR_ROOT)

.PHONY: install-pkg-kopia
install-pkg-kopia: $(INSTALL_PATH)/install_github_asset.sh $(KOPIA_STAMP)
	@echo "📦 Ensuring Kopia $(KOPIA_VERSION)"
	# Fast path: skip if stamp + binary hash match
	@if [ -f "$(KOPIA_STAMP)" ] && [ -x "$(INSTALL_PATH)/kopia" ]; then \
		CURRENT_SHA=$$(sha256sum "$(INSTALL_PATH)/kopia" | awk '{print $$1}'); \
		STAMP_SHA=$$($(run_as_root) grep -oP 'sha256=\K[a-f0-9]+' "$(KOPIA_STAMP)" || echo none); \
		if [ "$$CURRENT_SHA" = "$$STAMP_SHA" ]; then \
			echo "✅ Kopia $(KOPIA_VERSION) already installed (hash match)"; \
			exit 0; \
		fi; \
	fi
	@$(run_as_root) $(INSTALL_PATH)/install_github_asset.sh \
		"$(KOPIA_URL)" \
		"$(INSTALL_PATH)/kopia" \
		"$(KOPIA_SHA256)" \
		"$(KOPIA_STAMP)"

.PHONY: remove-pkg-kopia
remove-pkg-kopia:
	@$(call remove_file_or_link_if_exists,/usr/local/bin/kopia $(KOPIA_STAMP),kopia) || true
	@$(run_as_root) rm -rf /usr/local/kopia >/dev/null 2>&1 || true

# ------------------------------------------------------------
# ndppd
# ------------------------------------------------------------
enable-ndppd:
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
STAMP_CHECKMAKE   := $(STAMP_DIR_ROOT)/checkmake.installed

$(STAMP_CHECKMAKE): install-pkg-pandoc install-pkg-go ensure-git-detachedhead-silenced | $(STAMP_DIR_ROOT)
	@echo "📦 Checking checkmake (v$(CHECKMAKE_VERSION))"

	# Fast path
	@if [ -f "$(STAMP_CHECKMAKE)" ] && [ -f "$(CHECKMAKE_BIN)" ]; then \
		CURRENT_SHA=$$(sha256sum "$(CHECKMAKE_BIN)" | awk '{print $$1}'); \
		STAMP_SHA=$$(grep -oP 'sha256=\K[a-f0-9]+' "$(STAMP_CHECKMAKE)" || echo none); \
		if [ "$$CURRENT_SHA" = "$$STAMP_SHA" ]; then \
			echo "✅ checkmake v$(CHECKMAKE_VERSION) already installed (hash match)"; \
			exit 0; \
		fi; \
	fi

	# Build
	@{ \
		set -e; \
		mkdir -p "$(CHECKMAKE_SRC)"; \
		if [ -d "$(CHECKMAKE_SRC)/.git" ]; then \
			cd "$(CHECKMAKE_SRC)"; \
			git fetch --tags --quiet; \
			git checkout --quiet "v$(CHECKMAKE_VERSION)" || true; \
		else \
			git clone --quiet --depth 1 --branch "v$(CHECKMAKE_VERSION)" https://github.com/mrtazz/checkmake.git "$(CHECKMAKE_SRC)"; \
		fi; \
	}

	@{ \
		cd "$(CHECKMAKE_SRC)"; \
		$(call go_install_from_source,checkmake,github.com/mrtazz/checkmake/cmd/checkmake@v$(CHECKMAKE_VERSION)); \
	}

	# Write stamp
	@NEW_SHA=$$(sha256sum "$(CHECKMAKE_BIN)" | awk '{print $$1}'); \
	echo "version=$(CHECKMAKE_VERSION) sha256=$$NEW_SHA installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		| $(run_as_root) tee "$(STAMP_CHECKMAKE)" >/dev/null

ensure-git-detachedhead-silenced:
	@git config --global advice.detachedHead false || true

.PHONY: install-pkg-checkmake
install-pkg-checkmake: $(STAMP_CHECKMAKE)

.PHONY: remove-pkg-checkmake
remove-pkg-checkmake:
	@{ \
		$(call remove_file_or_link_if_exists,$(CHECKMAKE_BIN) $(STAMP_CHECKMAKE),checkmake); \
		$(run_as_root) rm -rf "$(CHECKMAKE_SRC)" || true; \
	}

# ------------------------------------------------------------
# strace
# ------------------------------------------------------------
install-pkg-strace:
	@if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "ℹ️ strace already ensured by core apt group"; \
	fi

remove-pkg-strace:
	@{ $(call apt_remove,strace) ; }

# ------------------------------------------------------------
# Headscale
# ------------------------------------------------------------
HEADSCALE_VERSION ?= v0.27.1

headscale-build: install-pkg-go ensure-host-default-route | $(STAMP_DIR_ROOT)
	@if command -v headscale >/dev/null 2>&1; then \
		CURRENT_VER=$$(headscale version | awk '{print $$3}'); \
		if [ "$$CURRENT_VER" = "$(HEADSCALE_VERSION)" ]; then \
			echo "✅ headscale $(HEADSCALE_VERSION) already installed (hash match)"; \
			exit 0; \
		fi; \
	fi
	@$(call go_install_from_source,headscale,github.com/juanfont/headscale/cmd/headscale@$(HEADSCALE_VERSION))
	@echo "✅ headscale $(HEADSCALE_VERSION) installed"

.PHONY: remove-pkg-headscale
remove-pkg-headscale:
	@$(call remove_file_or_link_if_exists,$(INSTALL_PATH)/headscale $(STAMP_DIR_ROOT)/headscale.installed,headscale)

# ------------------------------------------------------------
# Pandoc (pinned .deb)
# ------------------------------------------------------------
PANDOC_VERSION := 3.9.0.2
PANDOC_DEB_URL := https://github.com/jgm/pandoc/releases/download/3.9.0.2/pandoc-3.9.0.2-1-amd64.deb
PANDOC_SHA256  := 7d124235998ecd3cdd9a463b1e5f6691a178b6461824c29a36170a0882f05597

STAMP_PANDOC := $(STAMP_DIR_ROOT)/pandoc.installed

$(STAMP_PANDOC): | $(STAMP_DIR_ROOT)
	@echo "📦 Ensuring Pandoc $(PANDOC_VERSION)"

	# Fast path: skip if stamp + binary hash match
	@if [ -f "$(STAMP_PANDOC)" ] && [ -x "$(INSTALL_PATH)/pandoc" ]; then \
		CURRENT_SHA=$$(sha256sum "$(INSTALL_PATH)/pandoc" | awk '{print $$1}'); \
		STAMP_SHA=$$($(run_as_root) grep -oP 'sha256=\K[a-f0-9]+' "$(STAMP_PANDOC)" || echo none); \
		if [ "$$CURRENT_SHA" = "$$STAMP_SHA" ]; then \
			echo "✅ Pandoc $(PANDOC_VERSION) already installed (hash match)"; \
			exit 0; \
		fi; \
	fi

	# Install/update Pandoc
	@$(run_as_root) $(INSTALL_PATH)/install_github_asset.sh \
		"$(PANDOC_DEB_URL)" \
		"$(INSTALL_PATH)/pandoc" \
		"$(PANDOC_SHA256)" \
		"$(STAMP_PANDOC)"

.SILENT: $(STAMP_PANDOC)
install-pkg-pandoc: $(STAMP_PANDOC)

.PHONY: upgrade-pkg-pandoc
upgrade-pkg-pandoc: $(STAMP_PANDOC) ensure-host-default-route
	@echo "⬆️ Upgrading pandoc..."
	@$(call apt_update_if_needed)
	@$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y pandoc || true
	tmp=$$(mktemp -p /dev/shm homelab.pandoc.tmp.XXXXXX); dpkg-query -W -f='${Version}\n' pandoc > "$$tmp" 2>/dev/null || echo "unknown" > "$$tmp"; \
	echo "version=$$(cat $$tmp) upgraded_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		| $(run_as_root) tee $(STAMP_PANDOC) >/dev/null; \
	rm -f "$$tmp"
	@echo "✅ pandoc upgrade complete"

.PHONY: remove-pkg-pandoc
remove-pkg-pandoc:
	@if dpkg -s pandoc >/dev/null 2>&1; then \
		echo "🗑️ Removing pandoc (takes about 4 seconds)..."; \
		$(run_as_root) apt-get remove -y --allow-change-held-packages pandoc >/dev/null 2>&1; \
	fi

print-STAMP-KOPIA: | $(STAMP_DIR_ROOT) $(STAMP_KOPIA)
	@echo "STAMP_DIR_ROOT='$(STAMP_DIR_ROOT)'"
	@echo "STAMP_KOPIA='$(STAMP_KOPIA)'"

print-run-as-root:
	@printf 'run_as_root="%s"\n' "$(run_as_root)"

.PHONY: deps-probes
deps-probes: | $(STAMP_DIR_ROOT)
	@if [ -f "$(PROBES_STAMP)" ]; then \
		echo "⏩ deps-probes (fast-path OK)"; \
		exit 0; \
	fi

	@echo "🔍 Running full dependency probes (parallel)..."

	# Start all probes in parallel
	@{ $(call check_bootstrap_dns); } &
	@{ $(call verify_tailscale_repo); } &
	@{ cargo --version >/dev/null; } &
	@{ $(call ensure_service_enabled,router-prefix-watchdog,router-prefix-watchdog); } &
	@{ $(call ensure_service_enabled,vnstat,vnstat); } &
	@{ dpkg -s golang-go >/dev/null 2>&1 && touch "$(STAMP_DIR_ROOT)/legacy-go.1" || true; } &
	@{ dpkg -s golang-1.19-go >/dev/null 2>&1 && touch "$(STAMP_DIR_ROOT)/legacy-go.2" || true; } &

	# Wait for all background jobs and fail if any failed
	@wait || { echo "❌ deps-probes failed"; exit 1; }

	# Single atomic stamp write
	@if [ -f "$(STAMP_DIR_ROOT)/legacy-go.1" ] || [ -f "$(STAMP_DIR_ROOT)/legacy-go.2" ]; then \
		echo "legacy" > "$(STAMP_DIR_ROOT)/legacy-go.detected"; \
	fi

	# Write main fast-path stamp (user-owned)
	@echo "ok" | $(run_as_root) tee "$(PROBES_STAMP)" >/dev/null

	# Cleanup temp markers
	@$(run_as_root) rm -f "$(STAMP_DIR_ROOT)/legacy-go.1" "$(STAMP_DIR_ROOT)/legacy-go.2"

	@echo "✅ deps-probes complete (parallel)"

dns-ok: | $(STAMP_DIR_ROOT)
	@if [ -f "$(STAMP_DNS_OK)" ]; then \
		echo "⏩ dns-ok (fast-path OK)"; \
		exit 0; \
	fi
	@echo "🔍 Checking bootstrap DNS..."
	@$(call check_bootstrap_dns)
	@$(run_as_root) touch "$(STAMP_DNS_OK)"

tailscale-hygiene-ok: | $(STAMP_DIR_ROOT)
	@if [ -f "$(STAMP_TS_OK)" ]; then \
		echo "⏩ tailscale-hygiene-ok (fast-path OK)"; \
		exit 0; \
	fi
	@echo "🔍 Verifying Tailscale repo hygiene"
	@$(call verify_tailscale_repo)
	@$(run_as_root) touch "$(STAMP_TS_OK)"

cargo-ok: | $(STAMP_DIR_ROOT)
	@if [ -f "$(STAMP_CARGO_OK)" ]; then \
		echo "⏩ cargo-ok (fast-path OK)"; \
		exit 0; \
	fi
	@echo "🔍 Checking cargo presence..."
	@cargo --version >/dev/null
	@$(run_as_root) touch "$(STAMP_CARGO_OK)"

watchdog-ok: | $(STAMP_DIR_ROOT)
	@if [ -f "$(STAMP_WATCHDOG_OK)" ]; then \
		echo "⏩ watchdog-ok (fast-path OK)"; \
		exit 0; \
	fi
	@$(call ensure_service_enabled,router-prefix-watchdog,router-prefix-watchdog)
	@$(run_as_root) touch "$(STAMP_WATCHDOG_OK)"

vnstat-ok:| $(STAMP_DIR_ROOT)
	@if [ -f "$(STAMP_VNSTAT_OK)" ]; then \
		echo "⏩ vnstat-ok (fast-path OK)"; \
		exit 0; \
	fi
	@$(call ensure_service_enabled,vnstat,vnstat)
	@$(run_as_root) touch "$(STAMP_VNSTAT_OK)"

STAMP_HOST_ROUTE_OK := $(STAMP_DIR_ROOT)/host-default-route.ok

$(STAMP_HOST_ROUTE_OK): | $(STAMP_DIR_ROOT)
	@if [ -f "$@" ]; then \
		echo "⏩ ensure-host-default-route (fast-path OK)"; \
		exit 0; \
	fi
	@echo "🔍 Checking host default route..."
	@( SECS="$( $($(SOPS_BIN) -d "$(SECRETS_FILE)" | $(YQ) -r 'to_entries | .[] | "\(.key)=\(.value)"' )"; \
	export $$SECS; \
	IFACE=$$(ip route get "$$ROUTER_ADDR" | awk "/dev/ {print \$$5}"); \
	if [ -z "$$IFACE" ]; then echo "❌ Cannot determine host LAN interface"; exit 1; fi; \
	if ! ip route show default | grep -q "$$ROUTER_ADDR"; then \
		echo "⚠️ Default gateway missing, restoring..."; \
		$(run_as_root) ip route add default via "$$ROUTER_ADDR" dev "$$IFACE" || true; \
	fi; \
	echo "🟢 Default gateway OK"; \
	)
	@echo ok | $(run_as_root) tee "$@" >/dev/null

.PHONY: ensure-host-default-route
ensure-host-default-route: $(STAMP_HOST_ROUTE_OK)