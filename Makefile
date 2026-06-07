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

# Canonical entrypoint wrapper
# This file exists ONLY to forward to the real graph.

# ---------------------------------------------------------------------------
# Secrets are NEVER loaded into Make variables.
# Secrets are injected ONLY inside a single shell via sops exec-env.
# ---------------------------------------------------------------------------

# SOPS binary and secrets file
SOPS         ?= /usr/local/bin/sops
SECRETS_FILE ?= $(REPO_ROOT)/secrets.enc.yaml
export SECRETS_FILE

# Load non-secret config
include $(REPO_ROOT)/mk/config.mk

include $(REPO_ROOT)/mk/graph.mk

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
