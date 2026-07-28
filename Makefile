# Makefile

# Root of the repository (directory containing this Makefile).
# NOTE:
#   We intentionally avoid `git rev-parse --show-toplevel` here.
#   In chroot/container/bind‑mount environments, `.git/` may not be visible,
#   causing `git rev-parse` to return empty and silently break all includes.
#
#   Using $(firstword $(MAKEFILE_LIST)) ensures REPO_ROOT always resolves to
#   the directory containing the top-level Makefile, regardless of how many
#   other .mk files are included or where they live.
#
REPO_ROOT := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
export REPO_ROOT

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

# Canonical entrypoint wrapper
# This file exists ONLY to forward to the real graph.

# ---------------------------------------------------------------------------
# Secrets are NEVER loaded into Make variables.
# Secrets are injected ONLY inside a single shell via sops exec-env.
# ---------------------------------------------------------------------------

# SOPS binary and secrets file
SOPS_BIN := /usr/local/bin/sops

# Ensure SOPS can decrypt inside Make recipes
SOPS_AGE_KEY_FILE := /etc/sops/keys/age.key
SECRETS_FILE := $(REPO_ROOT)/secrets.enc.yaml

export SOPS_AGE_KEY_FILE
export SECRETS_FILE

# Load non-secret config
include $(REPO_ROOT)/mk/config.mk

# Load full homelab DAG only when NOT running LM Studio or debug targets
ifeq ($(LMSTUDIO_GOALS)$(DEBUG_GOALS),)
include $(REPO_ROOT)/mk/graph.mk
endif

# Global Makefile invariants
.PHONY: sanity
sanity: assert-sanity

.DEFAULT_GOAL := help

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

# ----------------------------------------------------------------------------
# SSH Config Rendering (deterministic, idempotent, non-secret)
# ----------------------------------------------------------------------------
# Renders ~/.ssh/config from config/ssh_config.tmpl using authoritative
# variables exported in config.mk. On Windows, the template is patched to
# disable multiplexing and relax StrictHostKeyChecking.
#
# Idempotent: ~/.ssh/config is only rewritten if the rendered output differs.
# Silent unless VERBOSE=1.
# ----------------------------------------------------------------------------
.PHONY: ssh-config
ssh-config: config/ssh_config.tmpl
	@[ "$(VERBOSE)" = "1" ] && echo "🔧 Rendering SSH config for platform: $(SSH_PLATFORM)"

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
	if ! cmp -s $$tmpfile ~/.ssh/config; then \
		[ "$(VERBOSE)" = "1" ] && echo "📝 Updating ~/.ssh/config for platform: $(SSH_PLATFORM)"; \
		mv $$tmpfile ~/.ssh/config; \
		echo "✅ ~/.ssh/config updated for platform: $(SSH_PLATFORM)"; \
	else \
		[ "$(VERBOSE)" = "1" ] && echo "ℹ️ ~/.ssh/config already up-to-date"; \
		rm $$tmpfile; \
	fi
