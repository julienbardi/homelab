# Makefile
# Canonical entrypoint wrapper
# This file exists ONLY to forward to the real graph.

VERBOSE ?= 0
export VERBOSE

.DEFAULT_GOAL := help

HOMELAB_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
export HOMELAB_DIR

include mk/graph.mk
include mk/help.mk