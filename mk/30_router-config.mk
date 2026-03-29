# mk/30_router_config.mk
# ------------------------------------------------------------
# GLOBAL CONFIGURATION
# ------------------------------------------------------------
#
# Purpose:
#   - Define all shared configuration variables
#   - Provide a single source of truth for paths, hosts, ports
#
# Contract:
#   - This file MUST NOT define targets or recipes
#   - This file MUST NOT perform side effects
#   - Variables defined here are read-only by convention
#
# Inclusion:
#   - MUST be included before any other module
# ------------------------------------------------------------

ROUTER_SCRIPTS   ?= /jffs/scripts

ROUTER_SRC_CADDY   := $(REPO_ROOT)router/caddy
ROUTER_SRC_SCRIPTS := $(REPO_ROOT)router/jffs/scripts

ROUTER_CADDYFILE_SRC := $(ROUTER_SRC_CADDY)/Caddyfile
ROUTER_CADDYFILE_DST := /jffs/caddy/Caddyfile
ROUTER_CADDY_BIN     := /tmp/mnt/sda/router/bin/caddy

# ------------------------------------------------------------
# Remote execution primitives
# ------------------------------------------------------------
# Use a distinct prefix so it never touches the local 'run_as_root'
ROUTER_REMOTE_BIN := /jffs/scripts/run-as-root
router_exec       := ssh -p $(ROUTER_SSH_PORT) $(ROUTER_HOST) $(ROUTER_REMOTE_BIN)

# ------------------------------------------------------------
# Installed helpers (overrideable for testing or alternate platforms)
# ------------------------------------------------------------
CERTS_CREATE ?= /jffs/scripts/certs-create.sh
CERTS_DEPLOY ?= /jffs/scripts/certs-deploy.sh
GEN_CLIENT_CERT    ?= /jffs/scripts/generate-client-cert.sh
GEN_CLIENT_WRAPPER ?= /jffs/scripts/gen-client-cert-wrapper.sh

# ------------------------------------------------------------
# Shell platform contract
# ------------------------------------------------------------

COMMON_SH_SRC := $(REPO_ROOT)router/jffs/scripts/common.sh
COMMON_SH_DST := $(ROUTER_SCRIPTS)/common.sh
