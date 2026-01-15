# Makefile
# Canonical entrypoint wrapper
# This file exists ONLY to forward to the real graph.

.DEFAULT_GOAL := help

.PHONY: help

help:
	@$(MAKE) --no-print-directory -f Makefile.help help

# Only load the real graph when not asking for help
ifneq ($(MAKECMDGOALS),help) 
include Makefile.real
endif
