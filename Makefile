# ====================================================================
# Homelab Orchestration Makefile
# ====================================================================

# Default goal only when no explicit target is given
ifeq ($(MAKECMDGOALS),)
.DEFAULT_GOAL := help
endif

# Root of the repository (directory containing this Makefile).
# Uses $(firstword $(MAKEFILE_LIST)) to ensure REPO_ROOT resolves correctly
# in chroot, container, and bind-mount environments where .git/ is absent.
REPO_ROOT := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
export REPO_ROOT

ifeq ($(REPO_ROOT),)
$(error ❌ REPO_ROOT is empty — run make from inside the homelab repo)
endif

# Load non-secret config early so STAMP_DIR_ROOT and other base paths are available
include $(REPO_ROOT)/mk/config.mk

# Platform Identification
UNAME_S := $(shell uname -s 2>/dev/null || echo Windows)

ifeq ($(UNAME_S),Windows)
    SSH_PLATFORM := windows
else
    SSH_PLATFORM := unix
endif
export SSH_PLATFORM

# Detect LM Studio targets
LMSTUDIO_GOALS := $(filter lmstudio% homelab-lmstudio homelab-all-lmstudio,$(MAKECMDGOALS))

# Detect debug targets
DEBUG_GOALS := $(filter debug-vars debug-targets,$(MAKECMDGOALS))

export VERBOSE ?= 0

# Normalize: if VERBOSE is non-numeric → set to 3
ifeq ($(shell printf "%s" "$(VERBOSE)" | grep -Eq '^[0-9]+$$' && echo num || echo str),str)
export VERBOSE := 3
endif

# Canonical entrypoint wrapper
# Do NOT load the DAG when running ssh-config
ifeq ($(MAKECMDGOALS),ssh-config)
    # skip DAG entirely
else
    include $(REPO_ROOT)/mk/graph.mk
endif

# --------------------------------------------------------------------
# Modular variable guard system (only when DAG is loaded)
# --------------------------------------------------------------------
define REQUIRE_VAR
$(if $($(1)),,$(error $(1) is not set — check mk/config.mk))
endef

REQUIRED_VARS := \
    INSTALL_PATH \
    INSTALL_SBIN_PATH \
    INSTALL_FILE_IF_CHANGED \
    INSTALL_FILES_IF_CHANGED \
    INSTALL_IF_CHANGED_EXIT_CHANGED \
    ROOT_UID \
    ROOT_GID \
    RUN_ROOT_SRC \
    IFC_V3_SINGLE_SRC \
    IFC_V3_PLURAL_SRC \
    COMMON_SRC \
    REPO_ROOT \
    SSH_PLATFORM \
    WG_PLAN_SUBNETS \
    YQ_GITHUB_REPO \
    YQ_VERSION \
    YQ_SHA256

$(foreach v,$(REQUIRED_VARS),$(eval $(call REQUIRE_VAR,$(v))))

# ----------------------------------------------------------------------------
# SSH Config Rendering (deterministic, idempotent, non-secret)
# ----------------------------------------------------------------------------
.PHONY: ssh-config
ssh-config: config/ssh_config.tmpl
	@if [ "$(VERBOSE)" -ge "2" ]; then echo "🔧 Rendering SSH config for platform: $(SSH_PLATFORM)"; fi

	@tmpfile=$$(mktemp); \
	if [ "$(SSH_PLATFORM)" = "windows" ]; then \
		sed \
			-e 's/ControlMaster auto/ControlMaster no/' \
			-e 's#ControlPath ~/.ssh/cm-%r@%h:%p#ControlPath none#' \
			-e 's/ControlPersist 10m/ControlPersist no/' \
			-e 's/StrictHostKeyChecking .*/StrictHostKeyChecking accept-new/' \
			< config/ssh_config.tmpl | envsubst > $$tmpfile; \
	else \
		envsubst < config/ssh_config.tmpl > $$tmpfile; \
	fi; \
	\
	chmod 0600 $$tmpfile; \
	mkdir -p ~/.ssh; \
	\
	if ! cmp -s $$tmpfile ~/.ssh/config; then \
		if [ "$(VERBOSE)" -ge "1" ]; then echo "🔄 Updating ~/.ssh/config for platform: $(SSH_PLATFORM)..."; fi; \
		mv $$tmpfile ~/.ssh/config; \
		echo "🚀 installed ~/.ssh/config for platform: $(SSH_PLATFORM)"; \
	else \
		if [ "$(VERBOSE)" -ge "0" ]; then echo "🟢 already up-to-date: ~/.ssh/config for platform: $(SSH_PLATFORM)"; fi; \
		rm $$tmpfile; \
	fi

# Global Makefile invariants
.PHONY: sanity
sanity: assert-sanity

.PHONY: all
all: homelab-all

.PHONY: debug-vars
debug-vars:
	@echo "MAKEFILE_LIST = $(MAKEFILE_LIST)"
	@echo "REPO_ROOT     = '$(REPO_ROOT)'"
	@echo "PWD           = '$(shell pwd)'"
	@echo "graph.mk path = '$(REPO_ROOT)/mk/graph.mk'"
	@echo "Exists?       = '$(shell test -f $(REPO_ROOT)/mk/graph.mk && echo YES || echo NO)'"

.PHONY: debug-targets
debug-targets:
	@$(MAKE) -pRrq : 2>/dev/null | \
	awk '/^[a-zA-Z0-9][^$$#\/\t=]*:([^=]|$$)/ {print $$1}' | sort -u

# Load LM Studio subsystem only when explicitly requested
ifneq ($(LMSTUDIO_GOALS),)
include $(REPO_ROOT)/mk/contracts/wsl2.mk
include $(REPO_ROOT)/mk/targets/lmstudio.mk
include $(REPO_ROOT)/mk/targets/lmstudio-service.mk
include $(REPO_ROOT)/mk/targets/lmstudio-all.mk
include $(REPO_ROOT)/mk/targets/lmstudio-uninstall.mk
include $(REPO_ROOT)/mk/targets/homelab-lmstudio.mk
include $(REPO_ROOT)/mk/targets/homelab-all-lmstudio.mk
include $(REPO_ROOT)/mk/targets/homelab-all-extend.mk
endif