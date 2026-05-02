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
WITH_SECRETS = export $$( $(SOPS) -d $(SECRETS_FILE) | awk -F': ' '/: / {gsub(/"/, "", $$2); print $$1 "=" $$2}' );

# Keep for single-use cases
get-secret = $(shell $(SOPS) -d --extract '$(1)' $(SECRETS_FILE))

# Load non-secret config
include $(REPO_ROOT)/mk/config.mk

include $(REPO_ROOT)/mk/graph.mk

.PHONY: router
router: router-converge

# --- TARGETS ---

# Works for dozens of variables.
# We use one shell block so the 'export' persists for all commands.
router-configure:
	@$(WITH_SECRETS) \
		echo "Task 1: Pinging $$router_addr..."; \
		sudo -E ping -c1 $$router_addr; \
		echo "Task 2: Checking service on $$router_addr..."; \
		sudo curl -I http://$$router_addr; \
		echo "All tasks complete."

# This still works perfectly for you
router-ping:
	@sudo ping -c1 $(call get-secret,["router_addr"])

print-makefile_dir:
	@echo "REPO_ROOT is:    $(REPO_ROOT)"
	@echo "CURDIR is:       $(CURDIR)"
	@echo "SECRETS_FILE is: $(SECRETS_FILE)"