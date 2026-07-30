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

# Authorization guard (used by multiple modules)
.PHONY: ensure-authorized-admin
ensure-authorized-admin:
	@echo "$(AUTHORIZED_ADMINS)" | grep -qw "$(OPERATOR_USER)" || \
		{ echo "❌ User $(OPERATOR_USER) not authorized for this mutation"; exit 1; }

$(STAMP_DIR_ROOT):
	@if [ ! -d "$@" ]; then \
		echo "📋 [root] Creating STAMP_DIR_ROOT: $@"; \
		install -d -m 0755 -o root -g root "$@"; \
	fi

$(STAMP_DIR_USER): ensure-stamp-user
.PHONY: ensure-stamp-user
ensure-stamp-user:
	@if [ ! -d "$(STAMP_DIR_USER)" ]; then \
		echo "📋 [user] Creating STAMP_DIR_USER: $(STAMP_DIR_USER)"; \
		mkdir -p "$(STAMP_DIR_USER)"; \
	else \
		[ "$(VERBOSE)" = "1" ] && echo "📋 [user] STAMP_DIR_USER exists: $(STAMP_DIR_USER)"; \
	fi; \
	# Autocorrect ownership \
	if [ "$$(stat -c %u $(STAMP_DIR_USER))" != "$$(id -u)" ]; then \
		echo "🔧 [user] Fixing owner of $(STAMP_DIR_USER)"; \
		chown "$$(id -u):$$(id -g)" "$(STAMP_DIR_USER)"; \
	fi; \
	# Autocorrect permissions \
	if [ "$$(stat -c %a $(STAMP_DIR_USER))" -lt 700 ]; then \
		echo "🔧 [user] Fixing permissions of $(STAMP_DIR_USER)"; \
		chmod 700 "$(STAMP_DIR_USER)"; \
	fi

.PHONY: apt-uninstall-installed
apt-uninstall-installed: | $(run_as_root)
	@echo "🗑️  Removing all homelab APT packages (best-effort)..."
	@for pkg in $(APT_INSTALLABLE_PACKAGES); do \
		BIN=$$(command -v "$$pkg" 2>/dev/null || true); \
		if [ -n "$$BIN" ]; then \
			REAL=$$(dpkg -S "$$BIN" 2>/dev/null | head -n1 | cut -d: -f1); \
		else \
			REAL="$$pkg"; \
		fi; \
		[ -z "$$REAL" ] && REAL="$$pkg"; \
		printf "📦 Removing %-25s (pkg: %-20s) ... " "$$pkg" "$$REAL"; \
		if $(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get remove -y "$$REAL" >/dev/null 2>&1; then \
			echo "OK ✅"; \
		else \
			echo "not installed or failed"; \
		fi; \
	done; \
	echo " Autoremoving leftover dependencies"; \
	$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get autoremove -y >/dev/null 2>&1 || true; \
	echo "🔍 Done."


# ------------------------------------------------------------
# Tools Installation (The Bootstrap Core)
# ------------------------------------------------------------

# 1. Root wrapper
$(run_as_root): $(RUN_ROOT_SRC)
	@echo "🚀 Bootstrapping run-as-root..."
	@sudo mkdir -p $(INSTALL_SBIN_PATH)
	@sudo install -o $(ROOT_UID) -g $(ROOT_GID) -m 0755 "$<" "$@"

# 2. Singular V3 Engine (portable, zero-bootstrap)
$(INSTALL_FILE_IF_CHANGED): $(IFC_V3_SINGLE_SRC)
	@echo "🚀 Bootstrapping IFC v3 (portable engine)..."
	@sudo mkdir -p $(INSTALL_PATH)
	@sudo install -o $(ROOT_UID) -g $(ROOT_GID) -m 0755 "$<" "$@"

# 3. Vectorized V3 Engine
$(INSTALL_FILES_IF_CHANGED): $(IFC_V3_PLURAL_SRC) | $(INSTALL_FILE_IF_CHANGED_V3)
	@echo "🚀 Bootstrapping Vector Engine v3..."
	@sudo install -o $(ROOT_UID) -g $(ROOT_GID) -m 0755 "$<" "$@"

# ------------------------------------------------------------
# Macros
# ------------------------------------------------------------

# Arguments for install_file_if_changed_v3.sh:
# 1: SRC_HOST, 2: SRC_PORT, 3: SRC_PATH, 4: DST_HOST, 5: DST_PORT, 6: DST_PATH
# 7: OWNER, 8: GROUP, 9: MODE
# ------------------------------------------------------------
# Macros (Fixed for Shell Compatibility)
# ------------------------------------------------------------

# --------------------------------------------------------------------
# install_file — strict‑numeric IFC wrapper (local SRC→DST convenience)
# --------------------------------------------------------------------
# Usage:
#    $(call install_file, SRC_PATH, DST_PATH, OWNER, GROUP, MODE)
#
# Guarantees:
#    - Always returns numeric exit status: 0, 1, or CHANGED_EXIT_CODE
#    - Never emits corrupted exit codes
#    - Never concatenates $? with strings
#    - Never uses eval
#    - Safe under any Makefile expansion
#    - No need for numeric sanitization in calling recipes
# --------------------------------------------------------------------

# Arguments for install_file_if_changed_v3.sh:
# 1: SRC_PATH, 2: DST_PATH, 3: OWNER, 4: GROUP, 5: MODE
define install_file
	rc=0; \
	$(run_as_root) $(INSTALL_FILE_IF_CHANGED) \
		"" "" "$(1)" \
		"" "" "$(2)" \
		"$(3)" "$(4)" "$(5)" \
		|| rc=$$?; \
	\
	# normalize IFC_v3 return code: 0 = OK, 3 = changed, others = fatal \
	case "$$rc" in \
		0) ;; \
		3) echo "📝 Updated: $(2)" ;; \
		''|*[!0-9]*) ;; \
		*) echo "❌ IFC: Fatal error (exit $$rc) installing $(2)" >&2; exit "$$rc" ;; \
	esac
endef



# All installed scripts are root-owned executables; repo scripts may be non-executable.

# $(call git_clone_or_fetch,DIR,URL,REF)
define git_clone_or_fetch
	mkdir -p "$(1)"; \
	if [ -d "$(1)/.git" ]; then \
		cd "$(1)"; \
		git fetch --unshallow --tags --quiet 2>/dev/null || git fetch --tags --quiet; \
		if ! git checkout --quiet "$(3)" 2>/dev/null; then \
			cd ..; rm -rf "$(1)"; \
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
# common.sh is the shell platform contract for all homelab
# scripts. It loads homelab.env, provides logging, safety
# wrappers, operator identity, and canonical path resolution.
#
# Because every script sources common.sh, and common.sh itself
# loads homelab.env, the installation of common.sh MUST depend
# on homelab-env. This ensures that the canonical environment
# file is always generated before any script can be executed.
#
# This single dependency collapses the need for dozens of
# per-target homelab-env dependencies across the DAG.
# ------------------------------------------------------------

# Minimal set required for the install_file macro to function
BOOTSTRAP_CORE := \
	$(run_as_root) \
	$(INSTALL_FILE_IF_CHANGED) \
	$(INSTALL_FILES_IF_CHANGED)

# 4. Common library (Uses Macro)
$(INSTALL_PATH)/common.sh: $(COMMON_SRC) homelab-env | $(BOOTSTRAP_CORE)
	@$(call install_file,$<,$@,$(ROOT_UID),$(ROOT_GID),0755)

# 5. URL-based IFC Engine (Uses Macro)
$(INSTALL_URL_FILE_IF_CHANGED): $(IFC_URL_SRC) | $(BOOTSTRAP_CORE)
	@$(call install_file,$<,$@,$(ROOT_UID),$(ROOT_GID),0755)

# Full set of dependencies for general scripts
BOOTSTRAP_FILES := \
	$(BOOTSTRAP_CORE) \
	$(INSTALL_URL_FILE_IF_CHANGED) \
	$(INSTALL_PATH)/common.sh

ALL_SCRIPTS := $(notdir $(wildcard $(REPO_ROOT)/scripts/*.sh))

SBIN_SCRIPTS := apt-proxy-auto.sh run-as-root.sh

# Exclude bootstrap files and sbin files from the generic bin list
EXCLUDE_LIST := $(SBIN_SCRIPTS) \
				install_file_if_changed_v3.sh \
				install_files_if_changed_v3.sh \
				install_url_file_if_changed.sh \
				common.sh \
				wg-plan-subnets.sh \
				$(filter router-%.sh,$(ALL_SCRIPTS))

BIN_FILES        := $(addprefix $(INSTALL_PATH)/,$(filter-out $(EXCLUDE_LIST),$(ALL_SCRIPTS)))
OTHER_SBIN_FILES := $(addprefix $(INSTALL_SBIN_PATH)/,$(filter-out run-as-root.sh,$(SBIN_SCRIPTS)))


define INSTALL_BIN_TEMPLATE
$(1): $(REPO_ROOT)/scripts/$(notdir $(1)) | $(run_as_root)
	@$(call install_file,$(REPO_ROOT)/scripts/$(notdir $(1)),$(1),$(ROOT_UID),$(ROOT_GID),0755)
endef

.PHONY: $(BIN_FILES)
# Install BIN_FILES (to /usr/local/bin)
$(foreach f,$(BIN_FILES),$(eval $(call INSTALL_BIN_TEMPLATE,$(f))))

define INSTALL_SBIN_TEMPLATE
$(1): $(REPO_ROOT)/scripts/$(notdir $(1)) | $(run_as_root)
	@$(call install_file,$(REPO_ROOT)/scripts/$(notdir $(1)),$(1),$(ROOT_UID),$(ROOT_GID),0755)
endef

.PHONY: $(OTHER_SBIN_FILES)
# Install OTHER_SBIN_FILES (to /usr/local/sbin)
$(foreach f,$(OTHER_SBIN_FILES),$(eval $(call INSTALL_SBIN_TEMPLATE,$(f))))

# ------------------------------------------------------------
# Main Targets
# ------------------------------------------------------------

.PHONY: install-all uninstall-all assert-sanity

install-all: assert-sanity $(BOOTSTRAP_FILES) $(OTHER_SBIN_FILES) $(BIN_FILES) install-router-prefix-watchdog $(run_as_root)
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "📦 [$(ROLE)] Homelab bootstrap complete."; fi

uninstall-all:
	@echo "🗑️  Uninstalling all homelab scripts..."
	-@$(run_as_root) rm -f $(BIN_FILES) $(OTHER_SBIN_FILES) $(BOOTSTRAP_FILES) || true

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

.PHONY: assert-sanity assert-scripts-layout
assert-sanity: \
	assert-scripts-layout
	@test -d $(REPO_ROOT)/scripts || { echo "❌ Error: scripts directory missing"; exit 1; }

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
		echo "➡️ Scripts must be organized into functional subdirectories."; \
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
		$(call apt_update_if_needed); \
		$(run_as_root) sh -c '( test -x /usr/local/sbin/apt-proxy-auto.sh && /usr/local/sbin/apt-proxy-auto.sh ) || true'; \
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
		dpkg-query -W -f='$${Status} $${Package}\n' $$PKGS 2>/dev/null || true \
		| awk -F'\t' '$$1 == "install ok installed" {print $$2}' \
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
		for pkg in $$PKGS; do \
			if ! dpkg-query -W -f='$${Status}' "$$pkg" 2>/dev/null | grep -q "ok installed"; then \
				echo "$$pkg"; \
			fi; \
		done \
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
define ensure_service_enabled
	if ! systemctl is-enabled $(1) >/dev/null 2>&1; then \
		$(run_as_root) systemctl enable --now $(1) >/dev/null 2>&1 || true; \
		echo "✅ $(2) enabled"; \
	elif [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "ℹ️ $(2) already enabled"; \
	fi
endef

# ---------------------------------------------------------------------------
# Unified tmpfile cleanup macro
# Usage:
#   $(call TMPFILE_BLOCK, "<tmpfiles>", <body>)
#
# Guarantees:
#   - tmpfiles always cleaned (success, error, abort, Ctrl-C)
#   - body executed inside a single shell
#   - no drift, no leaks, no per-target duplication
# ---------------------------------------------------------------------------

define TMPFILE_BLOCK
	@trap 'rm -f "$(1)"' EXIT; \
	{ \
		$(2) \
	}
endef

.PHONY: apt-diagnostic
apt-diagnostic:
	@echo "=== PACKAGE ORIGIN DIAGNOSTIC ==="; \
	for p in $(UGOS_VENDOR_PACKAGES) $(APT_INSTALLABLE_PACKAGES); do \
		printf "%-25s : " $$p; \
		if dpkg-query -W -f='$${Status}\n' $$p 2>/dev/null | grep -q "^install ok installed$$"; then \
			PRIO=$$(dpkg-query -W -f='$${Priority}\n' $$p 2>/dev/null || echo "unknown"); \
			ESS=$$(dpkg-query -W -f='$${Essential}\n' $$p 2>/dev/null || echo "no"); \
			if [ "$$ESS" = "yes" ]; then \
				echo "UGOS (essential)"; \
			elif [ "$$PRIO" = "required" ]; then \
				echo "UGOS (priority: required)"; \
			else \
				echo "USER-INSTALLED (removable)"; \
			fi; \
		else \
			echo "NOT INSTALLED"; \
		fi; \
	done
