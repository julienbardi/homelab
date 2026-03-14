# --------------------------------------------------------------------
# mk/01_common.mk
# --------------------------------------------------------------------
# CONTRACT:
# - Defines run_as_root := /usr/local/sbin/run-as-root.sh
# - All recipes must call $(run_as_root) with argv tokens.
# --------------------------------------------------------------------

INSTALL_PATH      ?= /usr/local/bin
INSTALL_SBIN_PATH ?= /usr/local/sbin

# Global Engine Pointers (V2 ONLY)
INSTALL_FILE_IF_CHANGED         := $(INSTALL_PATH)/install_file_if_changed_v2.sh
INSTALL_FILES_IF_CHANGED        := $(INSTALL_PATH)/install_files_if_changed_v2.sh
INSTALL_IF_CHANGED_EXIT_CHANGED ?= 3

# Source Paths
IFC_V2_SINGLE_SRC := $(MAKEFILE_DIR)scripts/install_file_if_changed_v2.sh
IFC_V2_PLURAL_SRC := $(MAKEFILE_DIR)scripts/install_files_if_changed_v2.sh
COMMON_SRC         := $(MAKEFILE_DIR)scripts/common.sh
RUN_ROOT_SRC       := $(MAKEFILE_DIR)scripts/run-as-root.sh

# ------------------------------------------------------------
# Tools Installation (The Bootstrap Core)
# ------------------------------------------------------------

# 1. Root wrapper must be installed first using standard host install
$(INSTALL_SBIN_PATH)/run-as-root.sh: $(RUN_ROOT_SRC)
	@echo "🛡️  Installing Root Wrapper: $@"
	@install -o root -g root -m 0755 $< $@

run_as_root := $(INSTALL_SBIN_PATH)/run-as-root.sh

# 2. Singular V2 Engine
$(INSTALL_PATH)/install_file_if_changed_v2.sh: $(IFC_V2_SINGLE_SRC) $(run_as_root)
	@echo "🚀 Installing Singular V2 Engine: $@"
	@$(run_as_root) install -o root -g root -m 0755 $< $@

# 3. Vectorized V2 Engine
$(INSTALL_PATH)/install_files_if_changed_v2.sh: $(IFC_V2_PLURAL_SRC) $(run_as_root)
	@echo "🚀 Installing Vectorized V2 Engine: $@"
	@$(run_as_root) install -o root -g root -m 0755 $< $@

# 4. Common library
$(INSTALL_PATH)/common.sh: $(COMMON_SRC) $(run_as_root)
	@echo "📦 Installing Common Lib: $@"
	@$(run_as_root) install -o root -g root -m 0755 $< $@

# ------------------------------------------------------------
# Macros
# ------------------------------------------------------------

# Arguments for install_file_if_changed_v2.sh:
# 1: SRC_HOST, 2: SRC_PORT, 3: SRC_PATH, 4: DST_HOST, 5: DST_PORT, 6: DST_PATH
# 7: OWNER, 8: GROUP, 9: MODE
define install_file
	{ $(run_as_root) env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) $(INSTALL_FILE_IF_CHANGED) -q \
		"" "" "$(1)" \
		"" "" "$(2)" \
		"$(3)" "$(4)" "$(5)" || [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; }
endef

define install_script
	$(call install_file,$(1),$(INSTALL_PATH)/$(2),$(OWNER),$(GROUP),$(MODE))
endef

define install_sbin_script
	$(call install_file,$(1),$(INSTALL_SBIN_PATH)/$(2),$(OWNER),$(GROUP),$(MODE))
endef

# ------------------------------------------------------------
# Script Discovery & Classification
# ------------------------------------------------------------

BOOTSTRAP_FILES := \
	$(run_as_root) \
	$(INSTALL_FILE_IF_CHANGED) \
	$(INSTALL_FILES_IF_CHANGED) \
	$(INSTALL_PATH)/common.sh \
	$(HOMELAB_ENV_DST)

# Pattern rules for general scripts
$(INSTALL_PATH)/%.sh: $(MAKEFILE_DIR)scripts/%.sh | $(BOOTSTRAP_FILES)
	@$(call install_script,$<,$(notdir $<))

$(INSTALL_SBIN_PATH)/%.sh: $(MAKEFILE_DIR)scripts/%.sh | $(BOOTSTRAP_FILES)
	@$(call install_sbin_script,$<,$(notdir $<))

SBIN_SCRIPTS := apt-proxy-auto.sh run-as-root.sh systemd-override-sync.sh
ALL_SCRIPTS  := $(notdir $(wildcard $(MAKEFILE_DIR)scripts/*.sh))

# Exclude bootstrap files and sbin files from the generic bin list
EXCLUDE_LIST := $(SBIN_SCRIPTS) \
                install_file_if_changed_v2.sh \
                install_files_if_changed_v2.sh \
                common.sh \
                install_file_if_changed.sh

BIN_FILES        := $(addprefix $(INSTALL_PATH)/,$(filter-out $(EXCLUDE_LIST),$(ALL_SCRIPTS)))
OTHER_SBIN_FILES := $(addprefix $(INSTALL_SBIN_PATH)/,$(filter-out run-as-root.sh,$(SBIN_SCRIPTS)))

OWNER ?= root
GROUP ?= root
MODE  ?= 0755

# ------------------------------------------------------------
# Main Targets
# ------------------------------------------------------------

.PHONY: install-all uninstall-all ensure-run-as-root assert-sanity

install-all: assert-sanity $(BOOTSTRAP_FILES) $(OTHER_SBIN_FILES) $(BIN_FILES)
	@echo "✅ System convergence complete."

uninstall-all:
	@echo "🗑️  Uninstalling all homelab scripts..."
	@$(run_as_root) rm -f $(BIN_FILES) $(OTHER_SBIN_FILES) $(BOOTSTRAP_FILES)

# ------------------------------------------------------------
# Environment
# ------------------------------------------------------------

HOMELAB_ENV_SRC := $(MAKEFILE_DIR)config/homelab.env
HOMELAB_ENV_DST := /volume1/homelab/homelab.env

$(HOMELAB_ENV_DST): $(HOMELAB_ENV_SRC) | $(INSTALL_FILE_IF_CHANGED)
	@$(run_as_root) install -d -o root -g root -m 0755 $(dir $@)
	@$(call install_file,$(HOMELAB_ENV_SRC),$@,root,root,0600)

ensure-run-as-root:
	@test -f "$(run_as_root)" || { echo "❌ Error: run-as-root.sh not found. Run 'sudo make install-all' first."; exit 1; }

assert-sanity:
	@test -d $(MAKEFILE_DIR)scripts || { echo "❌ Error: scripts directory missing"; exit 1; }