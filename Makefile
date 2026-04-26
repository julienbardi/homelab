# Makefile

# Prevent Make from treating the private key as a dependency
unexport SOPS_AGE_KEY_FILE
SOPS_AGE_KEY_FILE :=

# Canonical entrypoint wrapper
# This file exists ONLY to forward to the real graph.

.DEFAULT_GOAL := help

# Root of the Git repository (directory containing the top-level Makefile)
# Note: $(dir) explicitly includes the trailing slash.
REPO_ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# ONLY export the primary project root
export REPO_ROOT

include $(REPO_ROOT)mk/graph.mk

print-makefile_dir:
	@echo "REPO_ROOT is:    $(REPO_ROOT)"
	@echo "CURDIR is:       $(CURDIR)"

.PHONY: router
router: router-converge