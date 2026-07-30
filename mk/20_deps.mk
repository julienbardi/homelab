# mk/20_deps.mk

# --------------------------------------------------------------------
# Package installation and build helpers
# --------------------------------------------------------------------
STAMP_DNS_OK        := $(STAMP_DIR_ROOT)/dns-ok.stamp
STAMP_TS_OK         := $(STAMP_DIR_ROOT)/tailscale-hygiene.stamp
STAMP_WATCHDOG_OK   := $(STAMP_DIR_ROOT)/watchdog-ok.stamp
STAMP_VNSTAT_OK     := $(STAMP_DIR_ROOT)/vnstat-ok.stamp
PROBES_STAMP        := $(STAMP_DIR_ROOT)/deps-probes.checked
STAMP_PREREQS_OK    := $(STAMP_DIR_ROOT)/prereqs-ok.stamp
STAMP_INSTALLERS_OK := $(STAMP_DIR_ROOT)/installers-ok.stamp
STAMP_DEPS_OK       := $(STAMP_DIR_ROOT)/deps-ok.stamp
STAMP_GO            := $(STAMP_DIR_ROOT)/go.installed

GO_MODERN_VERSION := 1.25.5
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

SOPS_VERSION := v3.13.1
STAMP_SOPS   := $(STAMP_DIR_ROOT)/sops.installed

YQ_STAMP := $(STAMP_DIR_ROOT)/yq.installed

KOPIA_VERSION := 0.23.1
KOPIA_URL     := https://github.com/kopia/kopia/releases/download/v$(KOPIA_VERSION)/kopia_$(KOPIA_VERSION)_linux_$(GO_ARCH).deb
KOPIA_SHA256  := 3998c96b2db3410880ec8f6723f3c127248915896c22e6b882b352693230253a
KOPIA_STAMP   := $(STAMP_DIR_ROOT)/kopia.installed

CHECKMAKE_VERSION := 0.3.2
CHECKMAKE_BIN     := /usr/local/bin/checkmake
CHECKMAKE_SRC     := $(HOME)/src/checkmake
STAMP_CHECKMAKE   := $(STAMP_DIR_ROOT)/checkmake.installed

HEADSCALE_VERSION ?= v0.27.1
STAMP_HEADSCALE   := $(STAMP_DIR_ROOT)/headscale.installed

PANDOC_VERSION := 3.10.1
PANDOC_DEB_URL := https://github.com/jgm/pandoc/releases/download/3.10.1/pandoc-3.10.1-1-amd64.deb
PANDOC_SHA256  := b419369915e0f3181be0afdb040ec8ecc6b70e72e5992652a0d83aed9e6bc109
STAMP_PANDOC   := $(STAMP_DIR_ROOT)/pandoc.installed

INSTALLERS := go pandoc checkmake strace age rclone kopia sops yq
HYGIENE    := dns-ok tailscale-hygiene-ok watchdog-ok vnstat-ok prereqs-ok

# Stamp directory order-only dependencies (root scope)
$(STAMP_DNS_OK):        | $(STAMP_DIR_ROOT)
$(STAMP_TS_OK):         | $(STAMP_DIR_ROOT)
$(STAMP_WATCHDOG_OK):   | $(STAMP_DIR_ROOT)
$(STAMP_VNSTAT_OK):     | $(STAMP_DIR_ROOT)
$(PROBES_STAMP):        | $(STAMP_DIR_ROOT)
$(STAMP_PREREQS_OK):    | $(STAMP_DIR_ROOT)
$(STAMP_INSTALLERS_OK): | $(STAMP_DIR_ROOT)
$(STAMP_DEPS_OK):       | $(STAMP_DIR_ROOT)
$(STAMP_HOST_ROUTE_OK): | $(STAMP_DIR_ROOT)
$(STAMP_GO):            | $(STAMP_DIR_ROOT)

# ------------------------------------------------------------
# Generic helpers and macros
# ------------------------------------------------------------

# $(call write_stamp,STAMP_PATH,VERSION,FILE_PATH)
define write_stamp
	NEW_SHA=$$(sha256sum "$(3)" | awk '{print $$1}'); \
	TMP_STAMP=$$(mktemp); \
	echo "version=$(2) sha256=$$NEW_SHA installed_at=$$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$$TMP_STAMP"; \
	$(run_as_root) install -m 0644 "$$TMP_STAMP" "$(1)"; \
	rm -f "$$TMP_STAMP"
endef

# $(call fastpath_binary_with_stamp,STAMP_PATH,BIN_PATH,LABEL)
define fastpath_binary_with_stamp
	if [ -f "$(1)" ] && [ -x "$(2)" ]; then \
		CURRENT_SHA=$$(sha256sum "$(2)" | awk '{print $$1}'); \
		STAMP_SHA=$$($(run_as_root) grep -oP 'sha256=\K[a-f0-9]+' "$(1)" || echo none); \
		if [ "$$CURRENT_SHA" = "$$STAMP_SHA" ]; then \
			echo "⏩ $(3) unchanged (hash+stamp OK)"; \
			exit 0; \
		fi; \
	fi
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
	DEST="$(INSTALL_PATH)/$$BIN_NAME"; \
	STAMP="$(STAMP_DIR_ROOT)/$$BIN_NAME.installed"; \
	\
	$(call fastpath_binary_with_stamp,$$STAMP,$$DEST,$$BIN_NAME); \
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
	GOBIN=$$TMP_BIN $(GO_MODERN_BIN) install $$VERSION_STR || { echo "❌ Go build failed"; exit 1; }; \
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

# $(call remove_apt_pkg,PKGNAME)
define remove_apt_pkg
	@{ $(call apt_remove,$(1)) ; }
endef

# $(call ensure_service,SERVICE)
define ensure_service
	$(call ensure_service_enabled,$(1),$(1))
endef

# $(call remove_binary_with_stamp,BIN,STAMP,LABEL)
define remove_binary_with_stamp
	$(call remove_file_or_link_if_exists,$(1),$(3))
	$(run_as_root) rm -f "$(2)"
endef

# $(call install_github_asset,URL,DEST,SHA,STAMP)
define install_github_asset
	$(run_as_root) $(INSTALL_PATH)/install_github_asset.sh "$(1)" "$(2)" "$(3)" "$(4)"
endef

# $(call verbose_echo,MESSAGE)
define verbose_echo
	if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then echo "$(1)"; fi
endef

# Removes only regular files or symlinks.
define remove_file_or_link_if_exists
	sh -c '\
		DISPLAY_NAME="$(if $(1),$(shell basename "$(firstword $(1))"),files)"; \
		[ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ] && echo "ℹ️ Cleaning up $$DISPLAY_NAME"; \
		for item in $(1); do \
			[ -z "$$item" ] && continue; \
			LABEL="$(if $(2),$(2),$$item)"; \
			if [ ! -e "$$item" ]; then \
				$(call verbose_echo,ℹ️ Skipping (not found): $$item); \
				continue; \
			fi; \
			if [ -d "$$item" ]; then \
				echo "❌ ERROR: '\''$$LABEL'\'' is a directory. Refusing to delete directories." >&2; \
				exit 1; \
			fi; \
			if [ -L "$$item" ] || [ -f "$$item" ]; then \
				$(call verbose_echo,🗑️ Removing: $$item); \
				$(run_as_root) rm -f "$$item"; \
				continue; \
			fi; \
			echo "❌ ERROR: '\''$$LABEL'\'' is an unsupported type (not a file or symlink)." >&2; \
			exit 1; \
		done; \
		$(call verbose_echo,ℹ️ $$(echo "$$DISPLAY_NAME" | awk '\''{print toupper(substr($$0,1,1)) substr($$0,2)}'\'') removed); \
		exit 0; \
	'
endef

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

$(STAMP_INSTALLERS_OK): $(addprefix install-pkg-,$(INSTALLERS)) | $(STAMP_DIR_ROOT)
	@echo "ok" | $(run_as_root) tee "$@" >/dev/null

installers-ok: $(STAMP_INSTALLERS_OK)

$(STAMP_DEPS_OK): $(HYGIENE) installers-ok | $(STAMP_DIR_ROOT)
	@echo "ok" | $(run_as_root) tee "$@" >/dev/null
	@echo "✅ deps-ok complete"

deps-ok: $(STAMP_DEPS_OK)
deps: deps-ok

# ------------------------------------------------------------
# Tailscale repository
# ------------------------------------------------------------

tailscale-repo: ensure-host-default-route
	@echo "📦 Adding Tailscale apt repository (Debian $(DEBIAN_CODENAME))"
	@$(run_as_root) install -d -m 0755 /usr/share/keyrings
	@curl -fsSL https://pkgs.tailscale.com/stable/debian/$(DEBIAN_CODENAME).noarmor.gpg \
	| $(run_as_root) install -m 0644 -o "$(ROOT_UID)" -g "$(ROOT_GID)" /dev/stdin $(TS_REPO_KEYRING)
	@curl -fsSL https://pkgs.tailscale.com/stable/debian/$(DEBIAN_CODENAME).list \
	| $(run_as_root) install -m 0644 -o "$(ROOT_UID)" -g "$(ROOT_GID)" /dev/stdin $(TS_REPO_LIST)
	@$(call apt_update_if_needed)
	@echo "✅ Tailscale repository configured"

install-pkg-tailscale: tailscale-repo verify-pkg-tailscale ensure-host-default-route
	@echo "📦 Installing Tailscale (client + daemon)"
	@$(call apt_install_group,tailscale)
	@$(call ensure_service,tailscaled)
	@echo "✅ Tailscale installed and running"

upgrade-pkg-tailscale: tailscale-repo verify-pkg-tailscale ensure-host-default-route
	@echo "⬆️ Upgrading Tailscale to latest stable"
	@$(call apt_update_if_needed)
	@$(run_as_root) DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y tailscale
	@$(run_as_root) systemctl restart tailscaled >/dev/null 2>&1
	@echo "✅ Tailscale upgraded"

remove-pkg-tailscale:
	@$(call verbose_echo,🗑️ Removing Tailscale)
	@$(run_as_root) sh -c '\
		systemctl stop tailscaled >/dev/null 2>&1 || true; \
		systemctl disable tailscaled >/dev/null 2>&1 || true; \
	'
	@$(call remove_apt_pkg,tailscale)
	@$(call verbose_echo,✅ Tailscale removed)

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

install-pkg-go: | $(STAMP_DIR_ROOT)
	@echo "📦 go $(GO_MODERN_VERSION)"
	@$(call fastpath_binary_with_stamp,$(STAMP_GO),$(GO_MODERN_BIN),go)

	@set -e; \
	if [ -f "$(STAMP_DIR_ROOT)/legacy-go.detected" ]; then \
		echo "🗑️ Removing legacy apt Go version..."; \
		$(run_as_root) sh -c 'apt-get purge -y golang-go golang-1.19-go && apt-get autoremove -y'; \
	fi; \
	RET="$$( $(call fetch_tarball,$(GO_DIST_URL),$(GO_TARBALL)) )"; \
	echo "🚀 installing go $(GO_MODERN_VERSION)"; \
	$(call extract_tarball,$(GO_TARBALL),$(GO_MODERN_PREFIX)); \
	$(call install_symlink,$(GO_MODERN_BIN),/usr/local/bin/go); \
	$(call write_stamp,$(STAMP_GO),$(GO_MODERN_VERSION),$(GO_MODERN_BIN))
	@echo "✅ go ready"

remove-pkg-go:
	@$(call remove_binary_with_stamp,$(GO_MODERN_BIN) /usr/local/bin/go,$(STAMP_GO),go)

# ------------------------------------------------------------
# vnstat
# ------------------------------------------------------------

install-pkg-vnstat: prereqs-ok ensure-host-default-route
	@$(call verbose_echo,ℹ️ vnstat already ensured by core apt group)
	@if ! vnstat --iflist | grep -q tailscale0; then \
		echo "Initializing vnstat database for tailscale0..."; \
		$(run_as_root) vnstat --add -i tailscale0; \
	fi
	@$(call ensure_service,vnstat)
	@echo "✅ vnstat installed and initialized for tailscale0"

remove-pkg-vnstat:
	@$(call remove_apt_pkg,vnstat)

# ------------------------------------------------------------
# nftables
# ------------------------------------------------------------

install-pkg-nftables: prereqs-ok ensure-host-default-route
	@$(call verbose_echo,ℹ️ nftables already ensured by core apt group)
	@$(call ensure_service,nftables)

remove-pkg-nftables:
	@$(call remove_apt_pkg,nftables)

# ------------------------------------------------------------
# WireGuard
# ------------------------------------------------------------

install-pkg-wireguard: prereqs-ok ensure-host-default-route
	@$(call verbose_echo,ℹ️ WireGuard already ensured by core apt group)

remove-pkg-wireguard:
	@$(call remove_apt_pkg,wireguard wireguard-tools)

# ------------------------------------------------------------
# Caddy
# ------------------------------------------------------------

install-pkg-caddy: prereqs-ok ensure-host-default-route
	@$(call verbose_echo,ℹ️ Caddy already ensured by core apt group)

remove-pkg-caddy:
	@$(call remove_apt_pkg,caddy)
	@$(run_as_root) rm -f /etc/caddy/Caddyfile

# ------------------------------------------------------------
# Age (Source build via Go)
# ------------------------------------------------------------

install-pkg-age: | $(STAMP_DIR_ROOT)
	@echo "📦 age $(AGE_VERSION)"
	@$(call fastpath_binary_with_stamp,$(STAMP_AGE),$(AGE_BIN),age)
	@echo "🚀 installing age $(AGE_VERSION)"
	@$(call go_install_from_source,age,filippo.io/age/cmd/...@$(AGE_VERSION))
	@$(call write_stamp,$(STAMP_AGE),$(AGE_VERSION),$(AGE_BIN))
	@echo "✅ age ready"

remove-pkg-age:
	@$(call remove_binary_with_stamp,$(AGE_BIN) $(AGE_KEYGEN_BIN),$(STAMP_AGE),age)

# ------------------------------------------------------------
# SOPS (Secrets Operations - Source build via Go)
# ------------------------------------------------------------

install-pkg-sops: install-pkg-go | $(STAMP_DIR_ROOT)
	@echo "📦 sops $(SOPS_VERSION)"
	@$(call fastpath_binary_with_stamp,$(STAMP_SOPS),$(SOPS_BIN),sops)
	@echo "🚀 installing sops $(SOPS_VERSION)"
	@$(call go_install_from_source,sops,github.com/getsops/sops/v3/cmd/sops@$(SOPS_VERSION))
	@$(call write_stamp,$(STAMP_SOPS),$(SOPS_VERSION),$(SOPS_BIN))
	@echo "✅ sops ready"

remove-pkg-sops:
	@$(call remove_binary_with_stamp,$(SOPS_BIN),$(STAMP_SOPS),sops)

# ------------------------------------------------------------
# yq
# ------------------------------------------------------------

install-pkg-yq: $(INSTALL_PATH)/install_github_asset.sh | $(STAMP_DIR_ROOT)
	@echo "📦 yq $(YQ_VERSION)"
	@$(call fastpath_binary_with_stamp,$(YQ_STAMP),$(INSTALL_PATH)/yq,yq)
	@echo "🚀 installing yq $(YQ_VERSION)"
	@$(call install_github_asset,$(YQ_URL),$(INSTALL_PATH)/yq,$(YQ_SHA256),$(YQ_STAMP))
	@$(call write_stamp,$(YQ_STAMP),$(YQ_VERSION),$(INSTALL_PATH)/yq)
	@echo "✅ yq ready"

remove-pkg-yq:
	@$(call remove_binary_with_stamp,$(INSTALL_PATH)/yq,$(YQ_STAMP),yq)

# ------------------------------------------------------------
# Rclone
# ------------------------------------------------------------

install-pkg-rclone:
	@$(call verbose_echo,ℹ️ rclone already ensured by core apt group)

remove-pkg-rclone:
	@$(call remove_apt_pkg,rclone)

# ------------------------------------------------------------
# Kopia
# ------------------------------------------------------------

install-pkg-kopia: $(INSTALL_PATH)/install_github_asset.sh | $(STAMP_DIR_ROOT)
	@echo "📦 kopia $(KOPIA_VERSION)"
	@$(call fastpath_binary_with_stamp,$(KOPIA_STAMP),$(INSTALL_PATH)/kopia,kopia)
	@echo "🚀 installing kopia $(KOPIA_VERSION)"
	@$(call install_github_asset,$(KOPIA_URL),$(INSTALL_PATH)/kopia,$(KOPIA_SHA256),$(KOPIA_STAMP))
	@$(call write_stamp,$(KOPIA_STAMP),$(KOPIA_VERSION),$(INSTALL_PATH)/kopia)
	@echo "✅ kopia ready"

remove-pkg-kopia:
	@$(call remove_binary_with_stamp,/usr/local/bin/kopia,$(KOPIA_STAMP),kopia) || true
	@$(run_as_root) rm -rf /usr/local/kopia >/dev/null 2>&1 || true

# ------------------------------------------------------------
# ndppd
# ------------------------------------------------------------

enable-ndppd:
	@$(call verbose_echo,📦 Enabling ndppd service)
	@$(call ensure_service,ndppd)

# ------------------------------------------------------------
# checkmake
# ------------------------------------------------------------

install-pkg-checkmake: install-pkg-pandoc install-pkg-go ensure-git-detachedhead-silenced
	@echo "📦 checkmake $(CHECKMAKE_VERSION)"
	@$(call fastpath_binary_with_stamp,$(STAMP_CHECKMAKE),$(CHECKMAKE_BIN),checkmake)
	@echo "🚀 installing checkmake $(CHECKMAKE_VERSION)"
	@$(call git_checkout_version,https://github.com/mrtazz/checkmake.git,$(CHECKMAKE_VERSION),$(CHECKMAKE_SRC))
	@cd "$(CHECKMAKE_SRC)" && $(call go_install_from_source,checkmake,github.com/mrtazz/checkmake/cmd/checkmake@v$(CHECKMAKE_VERSION))
	@$(call write_stamp,$(STAMP_CHECKMAKE),$(CHECKMAKE_VERSION),$(CHECKMAKE_BIN))
	@echo "✅ checkmake ready"

ensure-git-detachedhead-silenced:
	@git config --global advice.detachedHead false || true

remove-pkg-checkmake:
	@$(call remove_binary_with_stamp,$(CHECKMAKE_BIN),$(STAMP_CHECKMAKE),checkmake)
	@$(run_as_root) rm -rf "$(CHECKMAKE_SRC)" || true

# ------------------------------------------------------------
# strace
# ------------------------------------------------------------

install-pkg-strace:
	@$(call verbose_echo,ℹ️ strace already ensured by core apt group)

remove-pkg-strace:
	@$(call remove_apt_pkg,strace)

# ------------------------------------------------------------
# Headscale
# ------------------------------------------------------------

headscale-build: install-pkg-go ensure-host-default-route | $(STAMP_DIR_ROOT)
	@$(call fastpath_binary_with_stamp,$(STAMP_HEADSCALE),$(INSTALL_PATH)/headscale,headscale)
	@$(call go_install_from_source,headscale,github.com/juanfont/headscale/cmd/headscale@$(HEADSCALE_VERSION))
	@$(call write_stamp,$(STAMP_HEADSCALE),$(HEADSCALE_VERSION),$(INSTALL_PATH)/headscale)
	@echo "✅ headscale $(HEADSCALE_VERSION) installed"

remove-pkg-headscale:
	@$(call remove_binary_with_stamp,$(INSTALL_PATH)/headscale,$(STAMP_HEADSCALE),headscale)

# ------------------------------------------------------------
# Pandoc
# ------------------------------------------------------------

install-pkg-pandoc: | $(STAMP_DIR_ROOT)
	@echo "📦 pandoc $(PANDOC_VERSION)"
	@$(call fastpath_binary_with_stamp,$(STAMP_PANDOC),$(INSTALL_PATH)/pandoc,pandoc)
	@echo "🚀 installing pandoc $(PANDOC_VERSION)"
	@$(call install_github_asset,$(PANDOC_DEB_URL),$(INSTALL_PATH)/pandoc,$(PANDOC_SHA256),$(STAMP_PANDOC))
	@$(call write_stamp,$(STAMP_PANDOC),$(PANDOC_VERSION),$(INSTALL_PATH)/pandoc)
	@echo "✅ pandoc ready"

upgrade-pkg-pandoc: $(STAMP_PANDOC) ensure-host-default-route
	@echo "⬆️ Upgrading pandoc..."
	@$(call apt_update_if_needed)
	@$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y pandoc || true
	@tmp=$$(mktemp -p /dev/shm homelab.pandoc.tmp.XXXXXX); dpkg-query -W -f='${Version}\n' pandoc > "$$tmp" 2>/dev/null || echo "unknown" > "$$tmp"; \
	$(call write_stamp,$(STAMP_PANDOC),$$(cat "$$tmp"),$(INSTALL_PATH)/pandoc); \
	rm -f "$$tmp"
	@echo "✅ pandoc upgrade complete"

remove-pkg-pandoc:
	@if dpkg -s pandoc >/dev/null 2>&1; then \
		echo "🗑️ Removing pandoc (takes about 4 seconds)..."; \
		$(run_as_root) apt-get remove -y --allow-change-held-packages pandoc >/dev/null 2>&1; \
	fi

# ------------------------------------------------------------
# deps-probes and hygiene stamps
# ------------------------------------------------------------

deps-probes: | $(STAMP_DIR_ROOT)
	@if [ -f "$(PROBES_STAMP)" ]; then \
		echo "⏩ deps-probes (fast-path OK)"; \
		exit 0; \
	fi

	@echo "🔍 Running full dependency probes (parallel)..."

	@{ $(call check_bootstrap_dns); } & \
	{ $(call verify_tailscale_repo); } & \
	{ $(call ensure_service,router-prefix-watchdog); } & \
	{ $(call ensure_service,vnstat); } & \
	{ dpkg -s golang-go >/dev/null 2>&1 && touch "$(STAMP_DIR_ROOT)/legacy-go.golang-go" || true; } & \
	{ dpkg -s golang-1.19-go >/dev/null 2>&1 && touch "$(STAMP_DIR_ROOT)/legacy-go.golang-1.19-go" || true; } &

	@wait || { echo "❌ deps-probes failed"; exit 1; }

	@if ls "$(STAMP_DIR_ROOT)"/legacy-go.* >/dev/null 2>&1; then \
		echo "legacy" > "$(STAMP_DIR_ROOT)/legacy-go.detected"; \
	fi

	@echo "ok" | $(run_as_root) tee "$(PROBES_STAMP)" >/dev/null
	@$(run_as_root) rm -f "$(STAMP_DIR_ROOT)/legacy-go.golang-go" "$(STAMP_DIR_ROOT)/legacy-go.golang-1.19-go"
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

watchdog-ok: | $(STAMP_DIR_ROOT)
	@if [ -f "$(STAMP_WATCHDOG_OK)" ]; then \
		echo "⏩ watchdog-ok (fast-path OK)"; \
		exit 0; \
	fi
	@$(call ensure_service,router-prefix-watchdog)
	@$(run_as_root) touch "$(STAMP_WATCHDOG_OK)"

vnstat-ok: | $(STAMP_DIR_ROOT)
	@if [ -f "$(STAMP_VNSTAT_OK)" ]; then \
		echo "⏩ vnstat-ok (fast-path OK)"; \
		exit 0; \
	fi
	@$(call ensure_service,vnstat)
	@$(run_as_root) touch "$(STAMP_VNSTAT_OK)"
