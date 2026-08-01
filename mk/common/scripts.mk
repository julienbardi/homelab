# ====================================================================
# mk/common/scripts.mk — Script Discovery & Installation
# ====================================================================
# All homelab scripts source common.sh, which loads homelab.env.
# Therefore common.sh MUST depend on homelab-env to guarantee the
# canonical environment is available before any script executes.
# ====================================================================


# --------------------------------------------------------------------
# Bootstrap prerequisites for script installation
# --------------------------------------------------------------------
BOOTSTRAP_FILES := \
	$(BOOTSTRAP_CORE) \
	$(INSTALL_URL_FILE_IF_CHANGED) \
	$(INSTALL_PATH)/common.sh


# --------------------------------------------------------------------
# Script Discovery
# --------------------------------------------------------------------
ALL_SCRIPTS := $(notdir $(wildcard $(REPO_ROOT)/scripts/*.sh))
SBIN_SCRIPTS := apt-proxy-auto.sh run-as-root.sh

# Exclusions: bootstrap engines, sbin scripts, router scripts, common.sh
EXCLUDE_LIST := \
	$(SBIN_SCRIPTS) \
	install_file_if_changed_v3.sh \
	install_files_if_changed_v3.sh \
	install_url_file_if_changed.sh \
	common.sh \
	wg-plan-subnets.sh \
	$(filter router-%.sh,$(ALL_SCRIPTS))

BIN_FILES        := $(addprefix $(INSTALL_PATH)/,$(filter-out $(EXCLUDE_LIST),$(ALL_SCRIPTS)))
OTHER_SBIN_FILES := $(addprefix $(INSTALL_SBIN_PATH)/,$(filter-out run-as-root.sh,$(SBIN_SCRIPTS)))


# --------------------------------------------------------------------
# Installation Templates
# --------------------------------------------------------------------
define INSTALL_BIN_TEMPLATE
$(1): $(REPO_ROOT)/scripts/$(notdir $(1)) | $(run_as_root)
	@$(call install_file,$(REPO_ROOT)/scripts/$(notdir $(1)),$(1),$(ROOT_UID),$(ROOT_GID),0755)
endef

.PHONY: $(BIN_FILES)
$(foreach f,$(BIN_FILES),$(eval $(call INSTALL_BIN_TEMPLATE,$(f))))

define INSTALL_SBIN_TEMPLATE
$(1): $(REPO_ROOT)/scripts/$(notdir $(1)) | $(run_as_root)
	@$(call install_file,$(REPO_ROOT)/scripts/$(notdir $(1)),$(1),$(ROOT_UID),$(ROOT_GID),0755)
endef

.PHONY: $(OTHER_SBIN_FILES)
$(foreach f,$(OTHER_SBIN_FILES),$(eval $(call INSTALL_SBIN_TEMPLATE,$(f))))


# --------------------------------------------------------------------
# Common Library (common.sh)
# --------------------------------------------------------------------
$(INSTALL_PATH)/common.sh: $(COMMON_SRC) homelab-env | $(BOOTSTRAP_CORE)
	@$(call install_file,$<,$@,$(ROOT_UID),$(ROOT_GID),0755)


# --------------------------------------------------------------------
# Main Targets
# --------------------------------------------------------------------
.PHONY: install-all uninstall-all assert-sanity

install-all: assert-sanity $(BOOTSTRAP_FILES) $(OTHER_SBIN_FILES) $(BIN_FILES) install-router-prefix-watchdog $(run_as_root)
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "📦 [$(ROLE)] Homelab bootstrap complete."; fi

uninstall-all:
	@echo "🗑️  Uninstalling all homelab scripts..."
	-@$(run_as_root) rm -f $(BIN_FILES) $(OTHER_SBIN_FILES) $(BOOTSTRAP_FILES) || true


# --------------------------------------------------------------------
# Script Preconditions
# --------------------------------------------------------------------
.PHONY: require-wg-plan-subnets
require-wg-plan-subnets:
	@test -x "$(WG_PLAN_SUBNETS)" || { \
		echo "❌ Missing $(WG_PLAN_SUBNETS). Run 'sudo make install-all' first."; \
		exit 1; \
	}


# --------------------------------------------------------------------
# Sanity Checks
# --------------------------------------------------------------------
.PHONY: assert-sanity assert-scripts-layout

assert-sanity: assert-scripts-layout
	@test -d $(REPO_ROOT)/scripts || { echo "❌ Error: scripts directory missing"; exit 1; }

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
