# ============================================================
# mk/40_wireguard.mk — Essential WireGuard workflow
# - Authoritative CSV -> validated compile -> atomic deploy
# - Using IFC V2 Engine (9-argument signature)
# ============================================================

WG_INPUT := $(WG_ROOT)/input
WG_CSV   := $(WG_INPUT)/clients.csv

WG_SCRIPTS_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../scripts)

# IFC V2 Engine Path
IFC_V2 := $(INSTALL_PATH)/install_file_if_changed_v2.sh

# ---------------------------------------------------------------------------
# Internal Macro: Push WG script to NAS via IFC v2
# ---------------------------------------------------------------------------
# We now use the global install_script macro to handle Exit Code 3 correctly.
define PUSH_WG_SCRIPT
	$(call install_script,$(1),$(notdir $(2)))
endef

# ---------------------------------------------------------------------------
# Script Path Definitions
# ---------------------------------------------------------------------------

WG_VALIDATE_SCRIPT                := $(WG_SCRIPTS_ROOT)/wg-validate-tsv.sh
WG_COMPILE_SCRIPT                 := $(WG_SCRIPTS_ROOT)/wg-compile.sh
WG_KEYS_SCRIPT                    := $(WG_SCRIPTS_ROOT)/wg-compile-keys.sh
WG_SERVER_KEYS_SCRIPT             := $(WG_SCRIPTS_ROOT)/wg-ensure-server-keys.sh
WG_RENDER_SCRIPT                  := $(WG_SCRIPTS_ROOT)/wg-compile-clients.sh
WG_RENDER_MISSING_SCRIPT          := $(WG_SCRIPTS_ROOT)/wg-render-missing-clients.sh
WG_EXPORT_SCRIPT                  := $(WG_SCRIPTS_ROOT)/wg-client-export.sh
WG_DEPLOY_SCRIPT                  := $(WG_SCRIPTS_ROOT)/wg-deploy.sh
WG_CHECK_SCRIPT                   := $(WG_SCRIPTS_ROOT)/wg-check.sh
WG_SERVER_BASE_RENDER_SCRIPT      := $(WG_SCRIPTS_ROOT)/wg-render-server-base.sh
WG_RENDER_CHECK_SCRIPT            := $(WG_SCRIPTS_ROOT)/wg-check-render.sh
WG_RECORD_COMPROMISED_KEYS_SCRIPT := $(WG_SCRIPTS_ROOT)/wg-record-compromised-keys.sh
WG_REMOVE_CLIENT                  := $(WG_SCRIPTS_ROOT)/wg-remove-client.sh
WG_ROTATE_CLIENT                  := $(WG_SCRIPTS_ROOT)/wg-rotate-client.sh
WG_PLAN_READ_SCRIPT               := $(WG_SCRIPTS_ROOT)/wg-plan-read.sh

WG_INSTALL_SOURCES := \
	$(WG_VALIDATE_SCRIPT) \
	$(WG_COMPILE_SCRIPT) \
	$(WG_KEYS_SCRIPT) \
	$(WG_SERVER_KEYS_SCRIPT) \
	$(WG_RENDER_SCRIPT) \
	$(WG_RENDER_MISSING_SCRIPT) \
	$(WG_EXPORT_SCRIPT) \
	$(WG_DEPLOY_SCRIPT) \
	$(WG_CHECK_SCRIPT) \
	$(WG_SERVER_BASE_RENDER_SCRIPT) \
	$(WG_RENDER_CHECK_SCRIPT) \
	$(WG_RECORD_COMPROMISED_KEYS_SCRIPT) \
	$(WG_REMOVE_CLIENT) \
	$(WG_ROTATE_CLIENT) \
	$(WG_PLAN_READ_SCRIPT) \
	$(WG_SCRIPTS_ROOT)/wg-qr.sh \
	$(WG_SCRIPTS_ROOT)/wg-runtime-recover.sh

# ---------------------------------------------------------------------------
# Install edges (repo -> $(INSTALL_PATH))
# ---------------------------------------------------------------------------

$(INSTALL_PATH)/wg-validate-tsv.sh: $(WG_VALIDATE_SCRIPT) | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

$(INSTALL_PATH)/wg-compile.sh: $(WG_COMPILE_SCRIPT) | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

$(INSTALL_PATH)/wg-compile-keys.sh: $(WG_KEYS_SCRIPT) | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

$(INSTALL_PATH)/wg-compile-clients.sh: $(WG_RENDER_SCRIPT) | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

$(INSTALL_PATH)/wg-render-missing-clients.sh: $(WG_RENDER_MISSING_SCRIPT) | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

$(INSTALL_PATH)/wg-client-export.sh: $(WG_EXPORT_SCRIPT) | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

$(INSTALL_PATH)/wg-deploy.sh: $(WG_DEPLOY_SCRIPT) | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

$(INSTALL_PATH)/wg-check.sh: $(WG_CHECK_SCRIPT) | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

$(INSTALL_PATH)/wg-render-server-base.sh: $(WG_SERVER_BASE_RENDER_SCRIPT) | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

$(INSTALL_PATH)/wg-check-render.sh: $(WG_RENDER_CHECK_SCRIPT) | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

$(INSTALL_PATH)/wg-record-compromised-keys.sh: $(WG_RECORD_COMPROMISED_KEYS_SCRIPT) | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

$(INSTALL_PATH)/wg-remove-client.sh: $(WG_REMOVE_CLIENT) | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

$(INSTALL_PATH)/wg-rotate-client.sh: $(WG_ROTATE_CLIENT) | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

$(INSTALL_PATH)/wg-plan-read.sh: $(WG_PLAN_READ_SCRIPT) | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

$(INSTALL_PATH)/wg-qr.sh: $(WG_SCRIPTS_ROOT)/wg-qr.sh | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

$(INSTALL_PATH)/wg-runtime-recover.sh: $(WG_SCRIPTS_ROOT)/wg-runtime-recover.sh | $(BOOTSTRAP_FILES)
	$(call PUSH_WG_SCRIPT,$<,$@)

# ---------------------------------------------------------------------------
# Install contract enforcement
# ---------------------------------------------------------------------------
$(foreach s, $(WG_INSTALL_SOURCES), \
	$(if $(shell test -x $(s) && echo ok),, \
		$(error Script not executable: $(s))))

.PHONY: wg-install-scripts wg-clean-out wg-validate-input wg-contract-check

wg-install-scripts: ensure-run-as-root \
	$(INSTALL_PATH)/wg-validate-tsv.sh \
	$(INSTALL_PATH)/wg-compile.sh \
	$(INSTALL_PATH)/wg-compile-keys.sh \
	$(INSTALL_PATH)/wg-ensure-server-keys.sh \
	$(INSTALL_PATH)/wg-compile-clients.sh \
	$(INSTALL_PATH)/wg-render-missing-clients.sh \
	$(INSTALL_PATH)/wg-client-export.sh \
	$(INSTALL_PATH)/wg-deploy.sh \
	$(INSTALL_PATH)/wg-check.sh \
	$(INSTALL_PATH)/wg-render-server-base.sh \
	$(INSTALL_PATH)/wg-check-render.sh \
	$(INSTALL_PATH)/wg-record-compromised-keys.sh \
	$(INSTALL_PATH)/wg-remove-client.sh \
	$(INSTALL_PATH)/wg-rotate-client.sh \
	$(INSTALL_PATH)/wg-plan-read.sh \
	$(INSTALL_PATH)/wg-qr.sh \
	$(INSTALL_PATH)/wg-runtime-recover.sh
	@true

wg-clean-out: ensure-run-as-root
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🧹 cleaning WireGuard scratch output"; fi
	@$(run_as_root) rm -rf "$(WG_ROOT)/out/clients"

wg-validate-input:
	@WG_ROOT="$(WG_ROOT)" $(run_as_root) scripts/wg-validate-tsv.sh

wg-contract-check:
	@echo "🔍 Checking WireGuard build contract"
	@$(foreach s,$(WG_INSTALL_SOURCES), test -x "$(s)" || { echo "❌ Script not executable: $(s)"; exit 1; } ;)
	@echo "✅ WireGuard build contract holds"


