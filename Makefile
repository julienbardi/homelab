# Makefile
# Canonical entrypoint wrapper
# This file exists ONLY to forward to the real graph.

.DEFAULT_GOAL := help

MAKEFILE_DIR := $(dir $(abspath $(firstword $(MAKEFILE_LIST))))

include $(MAKEFILE_DIR)mk/graph.mk
include $(MAKEFILE_DIR)mk/help.mk
