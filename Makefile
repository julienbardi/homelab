# Makefile
# Canonical entrypoint wrapper
# This file exists ONLY to forward to the real graph.

.DEFAULT_GOAL := help

# Root of the Git repository (directory containing the top-level Makefile), no trailing slash
REPO_ROOT := $(dir $(abspath $(firstword $(MAKEFILE_LIST))))
# Old name (kept temporarily for compatibility), no trailing slash
MAKEFILE_DIR := $(REPO_ROOT)

include $(MAKEFILE_DIR)mk/graph.mk

.PHONY: router
router: router-converge
