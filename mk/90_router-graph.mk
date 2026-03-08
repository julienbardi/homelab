# mk/graph.mk
# ------------------------------------------------------------
# ENTRYPOINT — GLOBAL DEPENDENCY GRAPH
# ------------------------------------------------------------
#
# Purpose:
#   - Assemble all modules into a single dependency graph
#   - Define inclusion order and global structure
#
# Inclusion order is significant:
#   1) config.mk     — shared variables (no targets, no recipes)
#   2) platform.mk   — shell ABI bootstrap (deploy-common)
#   3) router.mk     — router control plane
#   4) wireguard.mk  — WireGuard lifecycle
#   5) certs.mk      — certificate lifecycle
#   6) caddy.mk      — Caddy lifecycle
#   7) tools.mk      — local tooling
# ------------------------------------------------------------

include $(MAKEFILE_DIR)mk/config.mk
include $(MAKEFILE_DIR)mk/platform.mk
include $(MAKEFILE_DIR)mk/router.mk
include $(MAKEFILE_DIR)mk/wireguard.mk
include $(MAKEFILE_DIR)mk/certs.mk
include $(MAKEFILE_DIR)mk/caddy.mk
include $(MAKEFILE_DIR)mk/tools.mk
include $(MAKEFILE_DIR)mk/python.mk


.PHONY: all-full
all-full: all caddy
