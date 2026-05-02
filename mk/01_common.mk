# --------------------------------------------------------------------
# mk/01_common.mk
# --------------------------------------------------------------------
# CONTRACT:
# - Defines run_as_root := /usr/local/sbin/run-as-root.sh
# - All recipes must call $(run_as_root) with argv tokens.
# - Any target that executes $(run_as_root) MUST declare:
#       <target>: | $(run_as_root)
#   to ensure the wrapper exists before invocation.
# --------------------------------------------------------------------

# Deterministic PATH for all recipes
PATH := /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

APT_CORE_PACKAGES := \
	build-essential curl jq git nftables iptables shellcheck pup codespell \
	aspell aspell-en ndppd knot-dnsutils unbound unbound-anchor dnsutils \
	dnsperf iperf3 qrencode ripgrep htop libc-ares-dev apt-cacher-ng unzip \
	git-filter-repo python3-venv \
	wireguard wireguard-tools netfilter-persistent iptables-persistent \
	ethtool tcpdump \
	rclone

install-pkg-core-apt:
	@status=0; \
	$(call apt_install_group,$(APT_CORE_PACKAGES)) || status=$$?; \
	if [ "$$status" -eq 3 ]; then \
		: ; \
	elif [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "ℹ️ core apt group already satisfied"; \
	fi

# ------------------------------------------------------------
# Tools Installation (The Bootstrap Core)
# ------------------------------------------------------------

# 1. Root wrapper
$(run_as_root): $(RUN_ROOT_SRC)
	@echo "🚀 Bootstrapping run-as-root..."
	@sudo mkdir -p $(INSTALL_SBIN_PATH)
	@sudo install -o $(ROOT_UID) -g $(ROOT_GID) -m 0755 "$<" "$@"

# 2. Singular V2 Engine
$(INSTALL_FILE_IF_CHANGED): $(IFC_V2_SINGLE_SRC) | $(run_as_root)
	@echo "🚀 Bootstrapping IFC Engine..."
	@sudo mkdir -p $(INSTALL_PATH)
	@sudo install -o $(ROOT_UID) -g $(ROOT_GID) -m 0755 "$<" "$@"

# 3. Vectorized V2 Engine
$(INSTALL_FILES_IF_CHANGED): $(IFC_V2_PLURAL_SRC) | $(INSTALL_FILE_IF_CHANGED)
	@echo "🚀 Bootstrapping Vector Engine..."
	@sudo install -o $(ROOT_UID) -g $(ROOT_GID) -m 0755 "$<" "$@"

# ------------------------------------------------------------
# Macros
# ------------------------------------------------------------

# Arguments for install_file_if_changed_v2.sh:
# 1: SRC_HOST, 2: SRC_PORT, 3: SRC_PATH, 4: DST_HOST, 5: DST_PORT, 6: DST_PATH
# 7: OWNER, 8: GROUP, 9: MODE
# ------------------------------------------------------------
# Macros (Fixed for Shell Compatibility)
# ------------------------------------------------------------

# Arguments for install_file_if_changed_v2.sh:
# 1: SRC_PATH, 2: DST_PATH, 3: OWNER, 4: GROUP, 5: MODE
define install_file
	test -n "$(INSTALL_PATH)" || { echo "❌ Error: INSTALL_PATH is empty. Check mk/config.mk." >&2; exit 1; }; \
	status=0; \
	$(run_as_root) env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) $(INSTALL_FILE_IF_CHANGED) -q \
		"" "" "$(1)" \
		"" "" "$(2)" \
		"$(3)" "$(4)" "$(5)" || status=$$?; \
	{ [ $$status -eq 0 ] || [ $$status -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; } || { \
		echo "❌ IFC: Fatal error (exit $$status) installing $(2)" >&2; \
		exit $$status; \
	}; \
	[ $$status -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ] && echo "📝 Updated: $(2)" || true
endef

# All installed scripts are root-owned executables; repo scripts may be non-executable.
define install_script
	@$(call install_file,$(1),$(INSTALL_PATH)/$(2),$(ROOT_UID),$(ROOT_GID),0755)
endef

# $(call git_clone_or_fetch,DIR,URL,REF)
define git_clone_or_fetch
	mkdir -p "$(1)"; \
	if [ -d "$(1)/.git" ]; then \
		cd "$(1)"; \
		if ! git fetch --tags --quiet || ! git checkout --quiet "$(3)" 2>/dev/null; then \
			cd ..; \
			rm -rf "$(1)"; \
			git clone --quiet --depth 1 --branch "$(3)" "$(2)" "$(1)"; \
		fi; \
	else \
		git clone --quiet --depth 1 --branch "$(3)" "$(2)" "$(1)"; \
	fi
endef


# $(call acme_fix_perms,DIR)
# Ensures ACME directory permissions match ACME.sh security model.
define acme_fix_perms
	$(run_as_root) sh -c '\
		chown -R $(ROOT_UID):$(ROOT_GID) "$(1)"; \
		find "$(1)" -type d -exec chmod 0700 {} +; \
		find "$(1)" -type f -name "*.sh" -exec chmod 0755 {} +; \
		find "$(1)" -type f ! -name "*.sh" -exec chmod 0600 {} +; \
	'
endef

# ------------------------------------------------------------
# Script Discovery & Classification
# ------------------------------------------------------------

# Minimal set required for the install_file macro to function
BOOTSTRAP_CORE := \
	$(run_as_root) \
	$(INSTALL_FILE_IF_CHANGED) \
	$(INSTALL_FILES_IF_CHANGED)

# 4. Common library (Uses Macro)
$(INSTALL_PATH)/common.sh: $(COMMON_SRC) | $(BOOTSTRAP_CORE)
	@$(call install_file,$<,$@,$(ROOT_UID),$(ROOT_GID),0755)

# 5. URL-based IFC Engine (Uses Macro)
$(INSTALL_URL_FILE_IF_CHANGED): $(IFC_URL_SRC) | $(BOOTSTRAP_CORE)
	@$(call install_file,$<,$@,$(ROOT_UID),$(ROOT_GID),0755)

# Full set of dependencies for general scripts
BOOTSTRAP_FILES := \
	$(BOOTSTRAP_CORE) \
	$(INSTALL_URL_FILE_IF_CHANGED) \
	$(INSTALL_PATH)/common.sh

# Install only non-router scripts
$(INSTALL_PATH)/%.sh: $(REPO_ROOT)/scripts/%.sh | $(BOOTSTRAP_FILES)
	@$(call install_script,$<,$(notdir $<))

SBIN_SCRIPTS := apt-proxy-auto.sh run-as-root.sh
ALL_SCRIPTS := $(notdir $(wildcard $(REPO_ROOT)/scripts/*.sh))

# Exclude bootstrap files and sbin files from the generic bin list
EXCLUDE_LIST := $(SBIN_SCRIPTS) \
				install_file_if_changed_v2.sh \
				install_files_if_changed_v2.sh \
				install_url_file_if_changed.sh \
				install_file_if_changed.sh \
				common.sh \
				$(filter router-%.sh,$(ALL_SCRIPTS))

BIN_FILES        := $(addprefix $(INSTALL_PATH)/,$(filter-out $(EXCLUDE_LIST),$(ALL_SCRIPTS)))
OTHER_SBIN_FILES := $(addprefix $(INSTALL_SBIN_PATH)/,$(filter-out run-as-root.sh,$(SBIN_SCRIPTS)))

# ------------------------------------------------------------
# Main Targets
# ------------------------------------------------------------

.PHONY: install-all uninstall-all ensure-run-as-root assert-sanity

install-all: assert-sanity $(BOOTSTRAP_FILES) $(OTHER_SBIN_FILES) $(BIN_FILES)
	@echo "📦 [$(ROLE)] Homelab bootstrap complete."

uninstall-all:
	@echo "🗑️  Uninstalling all homelab scripts..."
	-@$(run_as_root) rm -f $(BIN_FILES) $(OTHER_SBIN_FILES) $(BOOTSTRAP_FILES) || true

ensure-run-as-root:
	@test -f "$(run_as_root)" || { echo "❌ Error: run-as-root.sh not found. Run 'sudo make install-all' first."; exit 1; }

.PHONY: require-wg-plan-subnets
require-wg-plan-subnets:
	@test -x "$(WG_PLAN_SUBNETS)" || { \
		echo "❌ Missing $(WG_PLAN_SUBNETS). Run 'sudo make install-all' first."; \
		exit 1; \
	}

# Invariant:
# - Make never executes scripts from the repo
# - All executable tools must be installed under $(INSTALL_PATH)
# - Targets depend on installed artifacts, not source files
# ------------------------------------------------------------

.PHONY: assert-sanity assert-no-repo-exec assert-scripts-layout
assert-sanity: \
	assert-no-repo-exec \
	assert-scripts-layout
	@test -d $(REPO_ROOT)/scripts || { echo "❌ Error: scripts directory missing"; exit 1; }

# Prevents race conditions and ensures we don't accidentally execute
# non-bootstrapped scripts from the working directory.
assert-no-repo-exec:
ifneq ($(filter -j%,$(MAKEFLAGS)),)
	@grep -R 'scripts/.*\.sh' --include='*.mk' \
		--exclude=01_common.mk \
		--exclude-dir=archive . >/dev/null && \
	{ \
		echo "🚫 Parallel execution (-j) is not supported."; \
		echo "   Safety checks detected repo-local script references during graph expansion."; \
		echo "   No scripts were executed."; \
		echo "   Rerun without -j (or use -j1)."; \
		exit 1; \
	}
endif

# Ensures all scripts reside in approved functional subdirectories.
assert-scripts-layout:
	@bad=$$(find "$(REPO_ROOT)/scripts" \
		-mindepth 2 -type f -name '*.sh' \
		! -path '*/_legacy_wireguard/*' \
		-print); \
	if [ -n "$$bad" ]; then \
		echo "❌ Layout Violation: Unexpected executable scripts found:"; \
		echo "$$bad" | sed 's/^/   - /'; \
		echo ""; \
		echo "👉 Scripts must be organized into functional subdirectories."; \
		exit 1; \
	fi

# ------------------------------------------------------------
# Package Management Macros (Perfected for Shell Nesting)
# ------------------------------------------------------------

# Arguments for apt_install:
# 1: PROBE_COMMAND (binary name), 2: PACKAGE_NAME
define apt_install
	@command -v $(1) >/dev/null 2>&1 || { \
		echo "apt 📦 Installing $(2)..."; \
		$(run_as_root) sh -c 'test -x /usr/local/sbin/apt-proxy-auto.sh && /usr/local/sbin/apt-proxy-auto.sh || true'; \
		$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get update -qq; \
		$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
			-o Dpkg::Options::="--force-confold" \
			-o Dpkg::Options::="--force-confdef" $(2); \
	}
endef


# ------------------------------------------------------------
# apt_remove
# Removes a group of apt packages in ONE resolver pass.
#
# Usage:
#   $(call apt_remove, pkg1 pkg2 pkg3 ...)
#
# Behavior:
#   - Silent unless VERBOSE=1
#   - Fast dpkg pre-probe: skip apt-get if nothing installed
#   - Removes only installed packages
#   - Privilege-correct: uses $(run_as_root)
#   - No multi-shell fragmentation
# ------------------------------------------------------------
define apt_remove
	PKGS="$(1)"; \
	if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "🗑️ Removing apt packages: $$PKGS"; \
	fi; \
	INSTALLED=$$( \
		dpkg-query -W -f='$${Status} $${Package}\n' $$PKGS 2>/dev/null \
		| awk '$$1$$2$$3 == "installokinstalled" {print $$4}' \
	); \
	if [ -z "$$INSTALLED" ]; then \
		if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
			echo "ℹ️ No packages to remove"; \
		fi; \
		exit 0; \
	fi; \
	if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "ℹ️ Installed packages to remove: $$INSTALLED"; \
	fi; \
	DEBIAN_FRONTEND=noninteractive $(run_as_root) apt-get remove -y --allow-change-held-packages $$INSTALLED >/dev/null 2>&1
endef


# Updates apt cache only if it hasn't been updated in the last hour.
define apt_update_if_needed
	$(run_as_root) sh -c 'test $$(find /var/lib/apt/lists -mmin -60 | grep -q .) || apt-get update -qq'
endef

# ------------------------------------------------------------
# apt_install_group
# Installs a group of apt packages in ONE resolver pass.
#
# Usage:
#   $(call apt_install_group, pkg1 pkg2 pkg3 ...)
#
# Behavior:
#   - Silent unless VERBOSE=1
#   - One dpkg/apt resolver pass (fast)
#   - Idempotent: does nothing if all packages already installed
#   - Privilege-correct: uses $(run_as_root)
#   - No multi-shell fragmentation
# ------------------------------------------------------------
define apt_install_group
	PKGS="$(1)"; \
	if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "📦 Installing apt package group: $$PKGS"; \
	fi; \
	MISSING=$$( \
		dpkg-query -W -f='$${Status} $${Package}\n' $$PKGS 2>/dev/null \
		| awk '$$1$$2$$3 != "installokinstalled" {print $$4}' \
	); \
	if [ -z "$$MISSING" ]; then \
		if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
			echo "ℹ️ core apt group already satisfied"; \
		fi; \
		exit 0; \
	fi; \
	if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "ℹ️ Missing packages: $$MISSING"; \
	fi; \
	DEBIAN_FRONTEND=noninteractive $(run_as_root) apt-get install -y --no-install-recommends $$MISSING
endef

# $(call ensure_service_enabled,<service>,<human-name>)
# $(call ensure_service_enabled,<service>,<human-name>)
define ensure_service_enabled
	if ! systemctl is-enabled $(1) >/dev/null 2>&1; then \
		$(run_as_root) systemctl enable --now $(1) >/dev/null 2>&1 || true; \
		echo "✅ $(2) enabled"; \
	elif [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "ℹ️ $(2) already enabled"; \
	fi
endef

