# Makefile

# Root of the Git repository (absolute, stable, canonical), no trailing slash
REPO_ROOT := $(shell git rev-parse --show-toplevel)
export REPO_ROOT

# Canonical entrypoint wrapper
# This file exists ONLY to forward to the real graph.

.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# Secrets are NEVER loaded into Make variables.
# Secrets are injected ONLY inside a single shell via sops exec-env.
# ---------------------------------------------------------------------------

# SOPS binary and secrets file
SOPS         ?= /usr/local/bin/sops
SECRETS_FILE ?= $(REPO_ROOT)/secrets.enc.yaml
export SECRETS_FILE

# THE FIX: Decrypt to a shell-compatible format and source it in-line.
# We use 'env' output from SOPS, which is naturally 'VAR=VAL'
# Legacy stub — do not use
WITH_SECRETS_LEGACY = export $$( $(SOPS) -d $(SECRETS_FILE) | awk -F': ' '/: / {gsub(/"/, "", $$2); print $$1 "=" $$2}' );

# Load non-secret config
include $(REPO_ROOT)/mk/config.mk

include $(REPO_ROOT)/mk/graph.mk

.PHONY: router
router: router-converge

router-configure:
	@$(call WITH_SECRETS, \
		echo "Task 1: Pinging $$ROUTER_ADDR..."; \
		sudo -E ping -c1 "$$ROUTER_ADDR"; \
		echo "Task 2: Checking service on $$ROUTER_ADDR..."; \
		sudo -E curl -I "http://$$ROUTER_ADDR"; \
		echo "All tasks complete."; \
	)
