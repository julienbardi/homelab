# mk/20_deps.mk

# --------------------------------------------------------------------
# Package installation and build helpers
# --------------------------------------------------------------------
STAMP_DNS_OK        := $(call STAMP_PATH_FROM_KEY,dns-ok)
STAMP_TS_OK         := $(call STAMP_PATH_FROM_KEY,tailscale-hygiene-ok)
STAMP_WATCHDOG_OK   := $(call STAMP_PATH_FROM_KEY,watchdog-ok)
STAMP_VNSTAT_OK     := $(call STAMP_PATH_FROM_KEY,vnstat-ok)
PROBES_STAMP        := $(call STAMP_PATH_FROM_KEY,deps-probes)
STAMP_PREREQS_OK    := $(call STAMP_PATH_FROM_KEY,prereqs-ok)
STAMP_INSTALLERS_OK := $(call STAMP_PATH_FROM_KEY,installers-ok)
STAMP_DEPS_OK       := $(call STAMP_PATH_FROM_KEY,deps-ok)
STAMP_HOST_ROUTE_OK := $(call STAMP_PATH_FROM_KEY,host-route-ok)
STAMP_GO            := $(call STAMP_PATH_FROM_KEY,go-$(GO_MODERN_VERSION))

GO_MODERN_VERSION := 1.27.0
GO_SHA256         := 675c26c449cbb18fc24b74650de1eabbae6e16f64326fd85a283fb3b58280685
export GO_SHA256
GO_MODERN_PREFIX  := /usr/local/go
GO_MODERN_BIN     := $(GO_MODERN_PREFIX)/bin/go
GO_ARCH           := amd64
GO_DIST_URL       := https://go.dev/dl/go$(GO_MODERN_VERSION).linux-$(GO_ARCH).tar.gz
GO_TARBALL        := $(STAMP_DIR_ROOT)/go$(GO_MODERN_VERSION).linux-$(GO_ARCH).tar.gz

DEBIAN_CODENAME ?= bookworm
TS_REPO_KEYRING := /usr/share/keyrings/tailscale-archive-keyring.gpg
TS_REPO_LIST    := /etc/apt/sources.list.d/tailscale.list

AGE_BIN        := /usr/local/bin/age
AGE_KEYGEN_BIN := /usr/local/bin/age-keygen
AGE_VERSION    := v1.2.1
STAMP_AGE      := $(STAMP_DIR_ROOT)/age.installed

SOPS_VERSION := v3.13.3
STAMP_SOPS   := $(STAMP_DIR_ROOT)/sops.installed

KOPIA_VERSION := 0.23.1
KOPIA_URL     := https://github.com/kopia/kopia/releases/download/v$(KOPIA_VERSION)/kopia_$(KOPIA_VERSION)_linux_$(GO_ARCH).deb
KOPIA_SHA256  := 3998c96b2db3410880ec8f6723f3c127248915896c22e6b882b352693230253a
KOPIA_STAMP   := $(STAMP_DIR_ROOT)/kopia.installed

CHECKMAKE_VERSION := 0.3.2
CHECKMAKE_BIN     := /usr/local/bin/checkmake
STAMP_CHECKMAKE   := $(STAMP_DIR_ROOT)/checkmake.installed

HEADSCALE_VERSION ?= v0.27.1
STAMP_HEADSCALE   := $(STAMP_DIR_ROOT)/headscale.installed

PANDOC_VERSION := 3.10.2
PANDOC_DEB_URL := https://github.com/jgm/pandoc/releases/download/$(PANDOC_VERSION)/pandoc-$(PANDOC_VERSION)-1-amd64.deb
PANDOC_SHA256  := sha256:6c06b69b49ae95087573631a6fcafb233ab7ab51e5cfa73f7539d6c964a2640d
STAMP_PANDOC   := $(STAMP_DIR_ROOT)/pandoc.installed

INSTALLERS := go pandoc checkmake strace age rclone kopia sops yq dnsdist
HYGIENE    := dns-ok tailscale-hygiene-ok watchdog-ok vnstat-ok prereqs-ok

# Stamp directory order-only dependencies (root scope)
$(STAMP_TS_OK):        ensure-state-dirs
$(STAMP_WATCHDOG_OK):  ensure-state-dirs
$(PROBES_STAMP):       ensure-state-dirs
$(STAMP_PREREQS_OK):    ensure-state-dirs
$(STAMP_INSTALLERS_OK): ensure-state-dirs
$(STAMP_DEPS_OK):       ensure-state-dirs
$(STAMP_HOST_ROUTE_OK): ensure-state-dirs
$(STAMP_GO):            ensure-state-dirs

# ------------------------------------------------------------
# Generic helpers and macros
# ------------------------------------------------------------

# $(call write_stamp,STAMP_PATH,VERSION,BIN_PATH)
define write_stamp
	STAMP_PATH="$(1)"; \
	VERSION_VAL="$(2)"; \
	BIN_PATH="$(3)"; \
	$(run_as_root) mkdir -p "$$$(dirname "$$STAMP_PATH")"; \
	_EX_SHA="$$([ -f "$$BIN_PATH" ] && sha256sum "$$BIN_PATH" 2>/dev/null | awk '{print $$1}' || echo "")"; \
	{ \
		echo "version=$$VERSION_VAL"; \
		echo "sha256=$$_EX_SHA"; \
		echo "owner=root"; \
		echo "group=root"; \
		echo "perm=0755"; \
		echo "type=regular"; \
	} | $(run_as_root) tee "$$STAMP_PATH" >/dev/null
endef

# $(call fastpath_binary_with_stamp,STAMP_PATH,BIN_PATH,LABEL)
define fastpath_binary_with_stamp
	([ -f "$(1)" ] && [ -x "$(2)" ] && \
	 CURRENT_SHA=$$(sha256sum "$(2)" | awk '{print $$1}') && \
	 STAMP_SHA=$$(grep '^sha256=' "$(1)" 2>/dev/null | cut -d= -f2- || echo "none") && \
	 [ -n "$$CURRENT_SHA" ] && [ "$$CURRENT_SHA" = "$$STAMP_SHA" ])
endef

# $(call install_binary_package,LABEL,VERSION,STAMP_PATH,BIN_PATH,INSTALL_CMD)
define install_binary_package
	@set -euo pipefail; \
	$(call verbose_echo,📦 $(1) $(2)); \
	if $(call fastpath_binary_with_stamp,$(3),$(4),$(1)); then \
		$(call verbose_echo,⏩ $(1) $(2) unchanged (hash+stamp OK)); \
		exit 0; \
	fi; \
	echo "🚀 installing $(1) $(2)"; \
	$(5); \
	$(call write_stamp,$(3),$(2),$(4)); \
	echo "✅ $(1) $(2) ready"
endef

# $(call ifc_install_dir,TMPDIR,INSTALL_PATH)
define ifc_install_dir
	for f in $(1)/*; do \
		FILENAME=$$(basename $$f); \
		TARGET="$(2)/$$FILENAME"; \
		echo "📦 Installing $$FILENAME via IFC"; \
		RC=0; \
		$(run_as_root) $(INSTALL_FILE_IF_CHANGED) -q "" "" "$$f" "" "" "$$TARGET" "$(ROOT_UID)" "$(ROOT_GID)" "0755" || RC=$$?; \
		if [ "$$RC" -ne 0 ] && [ "$$RC" -ne "$(INSTALL_IF_CHANGED_EXIT_CHANGED)" ]; then \
			echo "❌ IFC failed for $$TARGET (exit $$RC)"; \
			exit $$RC; \
		fi; \
	done
endef

# Macro: go_install_from_source
define go_install_from_source
	BIN_NAME="$(1)"; VERSION_STR="$(2)"; \
	REQ_VER="$${VERSION_STR##*@}"; \
	REQ_VER="$${REQ_VER#v}"; \
	DEST="$(INSTALL_PATH)/$$BIN_NAME"; \
	STAMP="$(STAMP_DIR_ROOT)/$$BIN_NAME.installed"; \
	\
	if [ ! -x "$(GO_MODERN_BIN)" ]; then \
		echo "❌ Go binary missing: $(GO_MODERN_BIN)"; \
		exit 1; \
	fi; \
	\
	echo "📦 Building $$BIN_NAME from source ($$VERSION_STR)..."; \
	TMP_BIN=$$(mktemp -p /dev/shm -d homelab.XXXXXX); \
	cleanup() { rm -rf "$$TMP_BIN"; }; \
	trap cleanup EXIT INT TERM; \
	\
	GOBIN=$$TMP_BIN $(GO_MODERN_BIN) install -trimpath $$VERSION_STR || { echo "❌ Go build failed"; exit 1; }; \
	$(call ifc_install_dir,$$TMP_BIN,$(INSTALL_PATH)); \
	$(call write_stamp,$$STAMP,$$REQ_VER,$$DEST)
endef

# $(call git_checkout_version,URL,VERSION,DEST)
define git_checkout_version
	set -e; \
	mkdir -p "$(3)"; \
	if [ -d "$(3)/.git" ]; then \
		cd "$(3)"; \
		git fetch --tags --quiet; \
		git checkout --quiet "v$(2)" || true; \
	else \
		git clone --quiet --depth 1 --branch "v$(2)" "$(1)" "$(3)"; \
	fi
endef

# $(call ensure_service,SERVICE)
define ensure_service
	$(call ensure_service_enabled,$(1),$(1))
endef

# $(call remove_binary_with_stamp,BIN,STAMP,LABEL[,EXTRA_PATH])
define remove_binary_with_stamp
	$(call remove_file_or_link_if_exists,$(1),$(3)); \
	$(run_as_root) rm -f "$(2)"; \
	if [ -n "$(4)" ]; then \
		$(call remove_file_or_link_if_exists,$(4),$(3) symlink); \
	fi; \
	$(call verbose_echo,🗑️ Removed $(3))
endef

# Removes a directory tree safely, restricted strictly to known homelab paths.
# $(call remove_directory_if_exists,DIR_PATH,LABEL)
define remove_directory_if_exists
	sh -c '\
		set -eu; \
		target="$(1)"; \
		case "$$target" in \
			/usr/local/go|/usr/local/go/*) ;; \
			*) \
				echo "❌ ERROR: Path '\''$$target'\'' is not on the approved removal whitelist." >&2; \
				exit 1; \
				;; \
		esac; \
		if [ -d "$$target" ]; then \
			$(call verbose_echo,🗑️ Removing directory: $$target); \
			$(run_as_root) rm -rf "$$target"; \
		fi; \
	'
endef

# $(call install_github_asset,URL,DEST,SHA,STAMP)
define install_github_asset
	$(run_as_root) $(INSTALL_PATH)/install_github_asset.sh "$(1)" "$(2)" "$(3)" "$(4)"
endef

# $(call verbose_echo,MESSAGE)
define verbose_echo
	if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then echo "$(1)"; fi
endef

# Removes only regular files or symlinks safely.
# $(call remove_file_or_link_if_exists,PATHS,LABEL)
define remove_file_or_link_if_exists
	sh -c '\
		set -eu; \
		for item in $(1); do \
			[ -z "$$item" ] && continue; \
			if [ ! -e "$$item" ]; then \
				continue; \
			fi; \
			if [ -d "$$item" ]; then \
				echo "❌ ERROR: '\''$$item'\'' is a directory. Refusing to delete directories." >&2; \
				exit 1; \
			fi; \
			if [ -L "$$item" ] || [ -f "$$item" ]; then \
				$(call verbose_echo,🗑️ Removing: $$item); \
				$(run_as_root) rm -f "$$item"; \
				continue; \
			fi; \
			echo "❌ ERROR: '\''$$item'\'' is an unsupported type (not a file or symlink)." >&2; \
			exit 1; \
		done; \
	'
endef

# $(call fetch_tarball,URL,TARBALL_PATH)
define fetch_tarball
	RET=0; \
	OUT="$$( $(run_as_root) "$(INSTALL_URL_FILE_IF_CHANGED)" \
		"$(1)" "$(2)" "$(ROOT_UID)" "$(ROOT_GID)" "0644" 2>&1 )" || RET=$$?; \
	if [ $$RET -ne 0 ]; then \
		echo "$$OUT" >&2; \
		exit $$RET; \
	fi
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

# ------------------------------------------------------------
# Phony targets
# ------------------------------------------------------------
.PHONY: deps remove-pkg-go \
    upgrade-pkg-pandoc remove-pkg-pandoc \
    remove-pkg-checkmake \
    remove-pkg-strace \
    install-pkg-vnstat remove-pkg-vnstat \
    install-pkg-tailscale upgrade-pkg-tailscale remove-pkg-tailscale \
    remove-pkg-age \
    remove-pkg-rclone \
    remove-pkg-kopia \
    headscale-build \
    installers-ok deps-ok deps \
    remove-pkg-sops remove-pkg-yq \
    enable-ndppd \
    install-pkg-strace \
    remove-pkg-headscale \
    deps-probes \
    dns-ok tailscale-hygiene-ok watchdog-ok vnstat-ok \
    install-pkg-go install-pkg-age install-pkg-sops install-pkg-yq \
    install-pkg-kopia install-pkg-pandoc install-pkg-checkmake

# ------------------------------------------------------------
# Aggregate installers/deps
# ------------------------------------------------------------

$(STAMP_INSTALLERS_OK): $(addprefix install-pkg-,$(INSTALLERS)) ensure-state-dirs
	@echo "ok" | $(run_as_root) tee "$@" >/dev/null

installers-ok: $(STAMP_INSTALLERS_OK)

$(STAMP_DEPS_OK): $(HYGIENE) installers-ok ensure-state-dirs
	@echo "ok" | $(run_as_root) tee "$@" >/dev/null
	@echo "✅ deps-ok complete"

deps-ok: $(STAMP_DEPS_OK)
deps: deps-ok

# ------------------------------------------------------------
# Tailscale repository
# ------------------------------------------------------------
.PHONY: tailscale-repo
tailscale-repo: ensure-host-default-route ensure-state-dirs
	@set -euo pipefail; \
	STAMP_PATH="$(call STAMP_PATH_FROM_KEY,tailscale-repo)"; \
	KEY_URL="https://pkgs.tailscale.com/stable/debian/$(DEBIAN_CODENAME).noarmor.gpg"; \
	KEY_PATH="$(TS_REPO_KEYRING)"; \
	LIST_PATH="$(TS_REPO_LIST)"; \
	EXPECTED_LIST="deb [signed-by=$$KEY_PATH] https://pkgs.tailscale.com/stable/debian $(DEBIAN_CODENAME) main"; \
	if [ -f "$$STAMP_PATH" ] && [ ! -L "$$STAMP_PATH" ] && [ -f "$$KEY_PATH" ] && [ -f "$$LIST_PATH" ]; then \
		_S_SHA="$$(grep '^sha256=' "$$STAMP_PATH" 2>/dev/null | cut -d= -f2- || echo "")"; \
		_CUR_SHA="$$(sha256sum "$$KEY_PATH" 2>/dev/null | awk '{print $$1}' || echo "")"; \
		if [ "$$_S_SHA" = "$$_CUR_SHA" ] && [ -n "$$_CUR_SHA" ] && grep -Fxq "$$EXPECTED_LIST" "$$LIST_PATH"; then \
			$(call verbose_echo,⏩ tailscale apt repository (Debian $(DEBIAN_CODENAME)) unchanged (fast-path OK)); \
			exit 0; \
		fi; \
	fi; \
	$(run_as_root) install -d -m 0755 /etc/apt/keyrings; \
	curl -fsSL "$$KEY_URL" | $(run_as_root) install -m 0644 -o "$(ROOT_UID)" -g "$(ROOT_GID)" /dev/stdin "$$KEY_PATH" || { echo "❌ tailscale key fetch failed"; exit 1; }; \
	echo "$$EXPECTED_LIST" | $(run_as_root) install -m 0644 -o "$(ROOT_UID)" -g "$(ROOT_GID)" /dev/stdin "$$LIST_PATH" || { echo "❌ tailscale list installation failed"; exit 1; }; \
	$(run_as_root) mkdir -p "$$(dirname "$$STAMP_PATH")"; \
	_CUR_SHA="$$(sha256sum "$$KEY_PATH" 2>/dev/null | awk '{print $$1}' || echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")"; \
	{ \
		echo "version=1"; \
		echo "sha256=$$_CUR_SHA"; \
		echo "owner=root"; \
		echo "group=root"; \
		echo "perm=0644"; \
		echo "type=probe"; \
	} | $(run_as_root) tee "$$STAMP_PATH" >/dev/null; \
	$(call apt_update_if_needed) || true; \
	$(call verbose_echo,✅ Tailscale apt repository (Debian $(DEBIAN_CODENAME)) configured)

.PHONY: install-pkg-tailscale upgrade-pkg-tailscale remove-pkg-tailscale
install-pkg-tailscale: tailscale-repo ensure-host-default-route ensure-state-dirs
	@set -euo pipefail; \
	STAMP_PATH="$(STAMP_DIR_ROOT)/tailscale.stamp"; \
	if [ -f "$$STAMP_PATH" ] && [ ! -L "$$STAMP_PATH" ] && dpkg -s tailscale >/dev/null 2>&1; then \
		_INST_VER="$$(dpkg-query -W -f='$${Version}' tailscale 2>/dev/null || echo "")"; \
		if [ -n "$$_INST_VER" ] && grep -q "^version=$${_INST_VER}$$" "$$STAMP_PATH" 2>/dev/null; then \
			$(call verbose_echo,⏩ tailscale unchanged (fast-path OK)); \
			exit 0; \
		fi; \
	fi; \
	$(call verbose_echo,🚀 installing tailscale); \
	$(call apt_install_group,tailscale) || { echo "❌ tailscale installation failed"; exit 1; }; \
	$(call ensure_service,tailscaled) || { echo "❌ tailscaled service activation failed"; exit 1; }; \
	$(run_as_root) mkdir -p "$$(dirname "$$STAMP_PATH")"; \
	_INST_VER="$$(dpkg-query -W -f='$${Version}' tailscale 2>/dev/null || echo "unknown")"; \
	{ \
		echo "version=$${_INST_VER}"; \
		echo "sha256=$$(dpkg -L tailscale 2>/dev/null | xargs sha256sum 2>/dev/null | awk '{print $$1}' | sha256sum | awk '{print $$1}' || echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")"; \
		echo "owner=root"; \
		echo "group=root"; \
		echo "perm=0755"; \
		echo "type=package"; \
	} | $(run_as_root) install -m 0644 /dev/stdin "$$STAMP_PATH"; \
	$(call verbose_echo,✅ Tailscale (client + daemon) installed and running)

upgrade-pkg-tailscale: tailscale-repo ensure-host-default-route
	@set -euo pipefail; \
	$(call verbose_echo,⬆️ Upgrading Tailscale to latest stable); \
	$(call apt_update_if_needed); \
	$(run_as_root) DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y tailscale; \
	$(run_as_root) systemctl restart tailscaled >/dev/null 2>&1; \
	STAMP_PATH="$(STAMP_DIR_ROOT)/tailscale.stamp"; \
	if [ -f "$$STAMP_PATH" ]; then \
		_INST_VER="$$(dpkg-query -W -f='$${Version}' tailscale 2>/dev/null || echo "unknown")"; \
		{ \
			echo "version=$$_INST_VER"; \
			echo "sha256=$$(dpkg -L tailscale 2>/dev/null | xargs sha256sum 2>/dev/null | awk '{print $$1}' | sha256sum | awk '{print $$1}' || echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")"; \
			echo "owner=root"; \
			echo "group=root"; \
			echo "perm=0755"; \
			echo "type=package"; \
		} | $(run_as_root) tee "$$STAMP_PATH" >/dev/null; \
	fi; \
	$(call verbose_echo,✅ Tailscale upgraded)

remove-pkg-tailscale:
	@set -euo pipefail; \
	$(run_as_root) sh -c ' \
		systemctl stop tailscaled >/dev/null 2>&1 || true; \
		systemctl disable tailscaled >/dev/null 2>&1 || true; \
	'; \
	$(call apt_remove,tailscale,$(STAMP_DIR_ROOT)/tailscale.stamp); \
	$(call verbose_echo,🗑️ Tailscale removed)

.PHONY: verify-pkg-tailscale
verify-pkg-tailscale: ensure-host-default-route
	@if ! dpkg -s tailscale >/dev/null 2>&1; then \
		echo "ℹ️ Tailscale is not installed (skipping verification)"; \
		exit 0; \
	fi; \
	bash -c 'set -e; \
		CLI_VER=$$(tailscale version | head -n1); \
		DS_VER=$$($(run_as_root) tailscaled --version | head -n1); \
		if [ "$$CLI_VER" != "$$DS_VER" ]; then \
			echo "❌ Version mismatch (CLI: $$CLI_VER, DAEMON: $$DS_VER)"; exit 1; \
		fi; \
		echo "✅ Tailscale versions aligned ($$CLI_VER)" \
	'

# ------------------------------------------------------------
# Go (Modern Binary Distribution)
# ------------------------------------------------------------

STAMP_GO := $(call STAMP_PATH_FROM_KEY,go)

.PHONY: install-pkg-go remove-pkg-go
install-pkg-go: ensure-state-dirs
	@set -euo pipefail; \
	$(call verbose_echo,📦 go $(GO_MODERN_VERSION)); \
	if [ -f "$(STAMP_GO)" ] && grep -q "version=$(GO_MODERN_VERSION)" "$(STAMP_GO)" 2>/dev/null && [ -f "$(GO_MODERN_BIN)" ]; then \
		$(call verbose_echo,⏩ go $(GO_MODERN_VERSION) unchanged (hash+stamp OK)); \
		exit 0; \
	fi; \
	if [ -f "$(STAMP_DIR_ROOT)/legacy-go.detected" ]; then \
		$(call verbose_echo,🗑️ Removing legacy apt Go version...); \
		$(run_as_root) sh -c 'apt-get purge -y golang-go golang-1.19-go && apt-get autoremove -y'; \
	fi; \
	$(call verbose_echo,🚀 installing go $(GO_MODERN_VERSION)); \
	CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(call fetch_tarball,$(GO_DIST_URL),$(GO_TARBALL),$(GO_SHA256)) \
		|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; \
	$(call extract_tarball,$(GO_TARBALL),$(GO_MODERN_PREFIX)) \
		|| { echo "❌ go extract failed"; exit 1; }; \
	env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(call install_symlink,$(GO_MODERN_BIN),/usr/local/bin/go) \
		|| [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; \
	$(call write_stamp,$(STAMP_GO),$(GO_MODERN_VERSION),$(GO_MODERN_BIN)); \
	$(call verbose_echo,✅ go $(GO_MODERN_VERSION) ready)

remove-pkg-go:
	@set -euo pipefail; \
	$(call remove_binary_with_stamp,$(GO_MODERN_BIN),$(STAMP_GO),Go $(GO_MODERN_VERSION),$(INSTALL_PATH)/go); \
	$(call remove_directory_if_exists,$(GO_MODERN_PREFIX),Go installation directory)

# ------------------------------------------------------------
# vnstat
# ------------------------------------------------------------

.PHONY: install-pkg-vnstat remove-pkg-vnstat
install-pkg-vnstat: prereqs-ok ensure-host-default-route
	@if [ "$(USE_TAILSCALED)" != "1" ]; then \
		echo "ℹ️ install-pkg-vnstat: USE_TAILSCALED=$(USE_TAILSCALED); skipping"; \
		exit 0; \
	fi; \
	$(call verbose_echo,ℹ️ vnstat already ensured by core apt group); \
	if ! vnstat --iflist | grep -q tailscale0; then \
		echo "Initializing vnstat database for tailscale0..."; \
		$(run_as_root) vnstat --add -i tailscale0; \
	fi; \
	$(call ensure_service,vnstat); \
	echo "✅ vnstat installed and initialized for tailscale0"

remove-pkg-vnstat:
	@set -euo pipefail; \
	if [ "$(USE_TAILSCALED)" != "1" ]; then \
		$(call verbose_echo,ℹ️ remove-pkg-vnstat: USE_TAILSCALED=$(USE_TAILSCALED); skipping); \
		exit 0; \
	fi; \
	$(call apt_remove,vnstat); \
	$(call verbose_echo,🗑️ vnstat removed)

# ------------------------------------------------------------
# nftables
# ------------------------------------------------------------

.PHONY: install-pkg-nftables remove-pkg-nftables
install-pkg-nftables: prereqs-ok ensure-host-default-route
	@$(call verbose_echo,ℹ️ nftables already ensured by core apt group)
	@$(call ensure_service,nftables)

remove-pkg-nftables:
	@set -euo pipefail; \
	$(call apt_remove,nftables); \
	$(call verbose_echo,🗑️ nftables removed)

# ------------------------------------------------------------
# WireGuard
# ------------------------------------------------------------

.PHONY: install-pkg-wireguard remove-pkg-wireguard
install-pkg-wireguard: prereqs-ok ensure-host-default-route
	@$(call verbose_echo,ℹ️ WireGuard already ensured by core apt group)

remove-pkg-wireguard:
	@set -euo pipefail; \
	$(call apt_remove,wireguard wireguard-tools); \
	$(call verbose_echo,🗑️ WireGuard removed)

# ------------------------------------------------------------
# Caddy
# ------------------------------------------------------------

install-pkg-caddy: prereqs-ok ensure-host-default-route
	@$(call verbose_echo,ℹ️ Caddy already ensured by core apt group)

remove-pkg-caddy:
	@set -euo pipefail; \
	$(call apt_remove,caddy); \
	$(call verbose_echo,🗑️ Caddy removed)

# ------------------------------------------------------------
# Age (Source build via Go)
# ------------------------------------------------------------

.PHONY: install-pkg-age
install-pkg-age: install-pkg-go ensure-state-dirs
	@set -euo pipefail; \
	$(call verbose_echo,📦 age $(AGE_VERSION)); \
	if $(call fastpath_binary_with_stamp,$(STAMP_AGE),$(AGE_BIN),age); then \
		$(call verbose_echo,⏩ age $(AGE_VERSION) unchanged (hash+stamp OK)); \
		exit 0; \
	fi; \
	$(call verbose_echo,🚀 installing age $(AGE_VERSION)); \
	TMP_BIN=$$(mktemp -p /dev/shm -d homelab.XXXXXX); \
	trap 'rm -rf "$$TMP_BIN"' EXIT; \
	GOBIN=$$TMP_BIN $(GO_MODERN_BIN) install filippo.io/age/cmd/age@$(AGE_VERSION); \
	GOBIN=$$TMP_BIN $(GO_MODERN_BIN) install filippo.io/age/cmd/age-keygen@$(AGE_VERSION); \
	$(call ifc_install_dir,$$TMP_BIN,$(INSTALL_PATH)); \
	$(call write_stamp,$(STAMP_AGE),$(AGE_VERSION),$(AGE_BIN)); \
	$(call verbose_echo,✅ age ready)

remove-pkg-age:
	@$(call remove_binary_with_stamp,$(AGE_BIN) $(AGE_KEYGEN_BIN),$(STAMP_AGE),age)

# ------------------------------------------------------------
# SOPS (Secrets Operations - Source build via Go)
# ------------------------------------------------------------

.PHONY: install-pkg-sops remove-pkg-sops
install-pkg-sops: install-pkg-go ensure-state-dirs
	@set -euo pipefail; \
	$(call verbose_echo,📦 sops $(SOPS_VERSION)); \
	if [ -f "$(STAMP_SOPS)" ] && grep -q "version=$(SOPS_VERSION)" "$(STAMP_SOPS)" 2>/dev/null && [ -f "$(SOPS_BIN)" ]; then \
		$(call verbose_echo,⏩ sops $(SOPS_VERSION) unchanged (hash+stamp OK)); \
		exit 0; \
	fi; \
	$(call verbose_echo,🚀 installing sops $(SOPS_VERSION)); \
	TMP_BIN=$$(mktemp -p /dev/shm -d homelab.XXXXXX); \
	trap 'rm -rf "$$TMP_BIN"' EXIT; \
	GOBIN=$$TMP_BIN $(GO_MODERN_BIN) install -trimpath github.com/getsops/sops/v3/cmd/sops@$(SOPS_VERSION); \
	$(call ifc_install_dir,$$TMP_BIN,$(INSTALL_PATH)); \
	$(call write_stamp,$(STAMP_SOPS),$(SOPS_VERSION),$(SOPS_BIN)); \
	$(call verbose_echo,✅ sops ready)

remove-pkg-sops:
	@$(call remove_binary_with_stamp,$(SOPS_BIN),$(STAMP_SOPS),sops)

# ------------------------------------------------------------
# yq
# ------------------------------------------------------------

.PHONY: install-pkg-yq remove-pkg-yq
install-pkg-yq: ensure-state-dirs $(INSTALL_PATH)/install_github_asset.sh
	@echo "📦 yq $(YQ_VERSION)"
	@if [ -f "$(YQ_STAMP)" ] && grep -q "version=$(YQ_VERSION)" "$(YQ_STAMP)" 2>/dev/null; then \
		[ "$(VERBOSE)" = "0" ] || echo "⏩ yq $(YQ_VERSION) unchanged (hash+stamp OK)"; \
	else \
		echo "⚙️ Installing/updating yq to $(YQ_VERSION)..."; \
		$(call install_github_asset,$(YQ_URL),$(INSTALL_PATH)/yq,$(YQ_SHA256),$(YQ_STAMP)); \
		$(call write_stamp,$(YQ_STAMP),$(YQ_VERSION),$(INSTALL_PATH)/yq); \
		echo "🟢 yq $(YQ_VERSION) installed and stamped successfully"; \
	fi

remove-pkg-yq:
	@$(call remove_binary_with_stamp,$(INSTALL_PATH)/yq,$(YQ_STAMP),yq)

# ------------------------------------------------------------
# Rclone
# ------------------------------------------------------------

install-pkg-rclone:
	@$(call verbose_echo,ℹ️ rclone already ensured by core apt group)

remove-pkg-rclone:
	@$(call apt_remove,rclone)

# ------------------------------------------------------------
# Kopia
# ------------------------------------------------------------

.PHONY: install-pkg-kopia remove-pkg-kopia
install-pkg-kopia: ensure-state-dirs $(INSTALL_PATH)/install_github_asset.sh
	@set -euo pipefail; \
	$(call verbose_echo,📦 kopia $(KOPIA_VERSION)); \
	if [ -f "$(KOPIA_STAMP)" ] && grep -q "version=$(KOPIA_VERSION)" "$(KOPIA_STAMP)" 2>/dev/null && [ -f "$(INSTALL_PATH)/kopia" ]; then \
		$(call verbose_echo,⏩ kopia $(KOPIA_VERSION) unchanged (hash+stamp OK)); \
		exit 0; \
	fi; \
	$(call verbose_echo,🚀 installing kopia $(KOPIA_VERSION)); \
	$(call install_github_asset,$(KOPIA_URL),$(INSTALL_PATH)/kopia,$(KOPIA_SHA256),$(KOPIA_STAMP)); \
	$(call write_stamp,$(KOPIA_STAMP),$(KOPIA_VERSION),$(INSTALL_PATH)/kopia); \
	$(call verbose_echo,✅ kopia ready)

remove-pkg-kopia:
	@$(call remove_binary_with_stamp,$(INSTALL_PATH)/kopia,$(KOPIA_STAMP),kopia)

# ------------------------------------------------------------
# ndppd
# ------------------------------------------------------------

enable-ndppd:
	@$(call verbose_echo,📦 Enabling ndppd service)
	@$(call ensure_service,ndppd)

# ------------------------------------------------------------
# checkmake
# ------------------------------------------------------------

STAMP_CHECKMAKE := $(call STAMP_PATH_FROM_KEY,checkmake)

.PHONY: install-pkg-checkmake
install-pkg-checkmake: install-pkg-go ensure-state-dirs
	@set -euo pipefail; \
	$(call verbose_echo,📦 checkmake $(CHECKMAKE_VERSION)); \
	if [ -f "$(STAMP_CHECKMAKE)" ] && grep -q "version=$(CHECKMAKE_VERSION)" "$(STAMP_CHECKMAKE)" 2>/dev/null && [ -f "$(CHECKMAKE_BIN)" ]; then \
		$(call verbose_echo,⏩ checkmake $(CHECKMAKE_VERSION) unchanged (hash+stamp OK)); \
		exit 0; \
	fi; \
	$(call verbose_echo,🚀 installing checkmake $(CHECKMAKE_VERSION)); \
	TMP_BIN=$$(mktemp -p /dev/shm -d homelab.XXXXXX); \
	trap 'rm -rf "$$TMP_BIN"' EXIT; \
	GOBIN=$$TMP_BIN $(GO_MODERN_BIN) install -trimpath github.com/checkmake/checkmake/cmd/checkmake@v$(CHECKMAKE_VERSION); \
	$(call ifc_install_dir,$$TMP_BIN,$(INSTALL_PATH)); \
	$(call write_stamp,$(STAMP_CHECKMAKE),$(CHECKMAKE_VERSION),$(CHECKMAKE_BIN)); \
	$(call verbose_echo,✅ checkmake ready)

ensure-git-detachedhead-silenced:
	@git config --global advice.detachedHead false || true

remove-pkg-checkmake:
	@$(call remove_binary_with_stamp,$(CHECKMAKE_BIN),$(STAMP_CHECKMAKE),checkmake)

# ------------------------------------------------------------
# strace
# ------------------------------------------------------------

install-pkg-strace:
	@$(call verbose_echo,ℹ️ strace already ensured by core apt group)

remove-pkg-strace:
	@$(call apt_remove,strace)

# ------------------------------------------------------------
# Headscale
# ------------------------------------------------------------

.PHONY: headscale-build remove-pkg-headscale
headscale-build: install-pkg-go ensure-host-default-route ensure-state-dirs
	@set -euo pipefail; \
	$(call verbose_echo,📦 headscale $(HEADSCALE_VERSION)); \
	if [ -f "$(STAMP_HEADSCALE)" ] && grep -q "version=$(HEADSCALE_VERSION)" "$(STAMP_HEADSCALE)" 2>/dev/null && [ -f "$(INSTALL_PATH)/headscale" ]; then \
		$(call verbose_echo,⏩ headscale $(HEADSCALE_VERSION) unchanged (hash+stamp OK)); \
		exit 0; \
	fi; \
	$(call verbose_echo,🚀 installing headscale $(HEADSCALE_VERSION)); \
	TMP_BIN=$$(mktemp -p /dev/shm -d homelab.XXXXXX); \
	trap 'rm -rf "$$TMP_BIN"' EXIT; \
	GOBIN=$$TMP_BIN $(GO_MODERN_BIN) install -trimpath github.com/juanfont/headscale/cmd/headscale@$(HEADSCALE_VERSION); \
	$(call ifc_install_dir,$$TMP_BIN,$(INSTALL_PATH)); \
	$(call write_stamp,$(STAMP_HEADSCALE),$(HEADSCALE_VERSION),$(INSTALL_PATH)/headscale); \
	$(call verbose_echo,✅ headscale $(HEADSCALE_VERSION) installed)

remove-pkg-headscale:
	@$(call remove_binary_with_stamp,$(INSTALL_PATH)/headscale,$(STAMP_HEADSCALE),headscale)

# ------------------------------------------------------------
# Pandoc
# ------------------------------------------------------------

STAMP_PANDOC := $(call STAMP_PATH_FROM_KEY,pandoc)

.PHONY: install-pkg-pandoc upgrade-pkg-pandoc remove-pkg-pandoc
install-pkg-pandoc: ensure-state-dirs
	@set -euo pipefail; \
	$(call verbose_echo,📦 pandoc $(PANDOC_VERSION)); \
	if $(call fastpath_binary_with_stamp,$(STAMP_PANDOC),$(INSTALL_PATH)/pandoc,pandoc); then \
		$(call verbose_echo,⏩ pandoc $(PANDOC_VERSION) unchanged (hash+stamp OK)); \
		exit 0; \
	fi; \
	$(call verbose_echo,🚀 installing pandoc $(PANDOC_VERSION)); \
	$(call install_github_asset,$(PANDOC_DEB_URL),$(INSTALL_PATH)/pandoc,$(PANDOC_SHA256),$(STAMP_PANDOC)) || { echo "❌ pandoc installation failed"; exit 1; }; \
	$(call write_stamp,$(STAMP_PANDOC),$(PANDOC_VERSION),$(INSTALL_PATH)/pandoc); \
	$(call verbose_echo,✅ pandoc $(PANDOC_VERSION) installed)

remove-pkg-pandoc:
	@$(call remove_binary_with_stamp,$(INSTALL_PATH)/pandoc,$(STAMP_PANDOC),pandoc)

# ------------------------------------------------------------
# deps-probes and hygiene stamps
# ------------------------------------------------------------

deps-probes: ensure-state-dirs
	@if [ -f "$(PROBES_STAMP)" ]; then \
		echo "⏩ deps-probes (fast-path OK)"; \
		exit 0; \
	fi
	@echo "🔍 Running full dependency probes (parallel)..."
	@bash -c '$(call check_bootstrap_dns)' & \
	bash -c '$(call verify_tailscale_repo)' & \
	bash -c '$(call ensure_service,router-prefix-watchdog)' & \
	bash -c '$(call ensure_service,vnstat)' & \
	bash -c 'dpkg -s golang-go >/dev/null 2>&1 && touch "$(STAMP_DIR_ROOT)/legacy-go.golang-go" || true' & \
	bash -c 'dpkg -s golang-1.19-go >/dev/null 2>&1 && touch "$(STAMP_DIR_ROOT)/legacy-go.golang-1.19-go" || true' & \
	wait || { echo "❌ deps-probes failed"; exit 1; }
	@if ls "$(STAMP_DIR_ROOT)"/legacy-go.* >/dev/null 2>&1; then \
		echo "legacy" > "$(STAMP_DIR_ROOT)/legacy-go.detected"; \
	fi
	@echo "ok" | $(run_as_root) tee "$(PROBES_STAMP)" >/dev/null
	@$(run_as_root) rm -f "$(STAMP_DIR_ROOT)/legacy-go.golang-go" "$(STAMP_DIR_ROOT)/legacy-go.golang-1.19-go"
	@echo "✅ deps-probes complete (parallel)"

$(eval $(call STAMPED_PROBE,dns-ok,\
	echo "🔍 Running probe dns-ok..." && \
	bash -c '$(call check_bootstrap_dns)',\
	1))

$(eval $(call STAMPED_PROBE,tailscale-hygiene-ok,\
	echo "🔍 Verifying Tailscale repo hygiene..." && \
	bash -c '$(call verify_tailscale_repo)',\
	1))

$(eval $(call STAMPED_PROBE,watchdog-ok,\
	echo "🔍 Ensuring watchdog service..." && \
	bash -c '$(call ensure_service,router-prefix-watchdog)',\
	1))

$(eval $(call STAMPED_PROBE,vnstat-ok,\
	if [ "$(USE_TAILSCALED)" = "1" ]; then \
		echo "🔍 Verifying vnstat service..." && \
		$(call ensure_service,vnstat); \
	fi,\
	1))