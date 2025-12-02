# mk/20_deps.mk
# Package installation and build helpers

.PHONY: deps install-pkg-go remove-pkg-go \
	install-pkg-pandoc upgrade-pkg-pandoc remove-pkg-pandoc \
	install-pkg-checkmake remove-pkg-checkmake \
	install-pkg-strace remove-pkg-strace \
	install-pkg-vnstat remove-pkg-vnstat \
	headscale-build

deps: install-pkg-go install-pkg-pandoc install-pkg-checkmake install-pkg-strace install-pkg-vnstat

# Use apt_install macro from mk/01_common.mk
install-pkg-go:
	$(call apt_install,go,golang-go)

remove-pkg-go:
	$(call apt_remove,golang-go)

# vnstat (network traffic monitor)
install-pkg-vnstat:
	$(call apt_install,vnstat,vnstat)
	@echo "[make] Initializing vnstat database for tailscale0..."
	@$(run_as_root) vnstat -u -i tailscale0 || true
	@$(run_as_root) systemctl enable --now vnstat || true
	@echo "[make] vnstat installed and initialized for tailscale0"

remove-pkg-vnstat:
	$(call apt_remove,vnstat)

# checkmake (build from upstream Makefile)
install-pkg-checkmake: install-pkg-pandoc install-pkg-go
	@echo "[make] Installing checkmake (v0.2.2) using upstream Makefile..."
	@mkdir -p $(HOME)/src
	@rm -rf $(HOME)/src/checkmake
	@git clone https://github.com/mrtazz/checkmake.git $(HOME)/src/checkmake
	@cd $(HOME)/src/checkmake && git config advice.detachedHead false && git checkout 0.2.2
	@cd $(HOME)/src/checkmake && \
	BUILDER_NAME="$$(git config --get user.name)" \
	BUILDER_EMAIL="$$(git config --get user.email)" \
	make
	@sudo install -m 0755 $(HOME)/src/checkmake/checkmake /usr/local/bin/checkmake
	@echo "[make] Installed checkmake built by $$(git config --get user.name) <$$(git config --get user.email)>"
	@checkmake --version

remove-pkg-checkmake:
	$(call remove_cmd,checkmake,rm -f /usr/local/bin/checkmake && rm -rf $(HOME)/src/checkmake)

# strace (used for debugging)
install-pkg-strace:
	$(call apt_install,strace,strace)

remove-pkg-strace:
	$(call apt_remove,strace)

# Headscale build (remote install fallback to upstream release)
headscale-build: install-pkg-go
	@echo "[make] Building Headscale..."
	@if ! command -v headscale >/dev/null 2>&1; then \
	GOBIN=$(INSTALL_PATH) go install github.com/juanfont/headscale/cmd/headscale@v0.27.1; \
	else \
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
STAMP_DIR ?= /var/lib/homelab
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
	@DEBIAN_FRONTEND=noninteractive sudo apt-get update
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
