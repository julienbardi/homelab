# mk/00_constants.mk
# ============================================================================
# mk/00_constants.mk — Canonical build-time constants
# ----------------------------------------------------------------------------
# PURPOSE:
#   This file defines the authoritative, side-effect-free constants used by
#   the homelab Make DAG. These values describe identities, paths, roles, and
#   network coordinates, but MUST NOT perform actions or depend on runtime
#   state.
#
# CONTRACT:
#   - Variables in this file are declarative only.
#   - No commands, no filesystem mutation, no network access.
#   - No secrets, credentials, tokens, or derived secret material.
#   - Values here may be exported, but never computed from secret content.
#   - Shell invocations are permitted ONLY for local identity discovery
#     and deterministic, read-only derivation (no mutation, no secrets).
#
# SCOPE:
#   - Operator identity (local, non-root)
#   - Canonical paths (NAS, router, tooling)
#   - Network identities and roles
#   - Build-time defaults and invariants
#
# NON-GOALS:
#   - Runtime configuration
#   - Secret validation or handling
#   - Host-specific probing or mutation
#
# Any logic, validation, or side effects MUST live in later mk/* layers.
# ============================================================================

# ------------------------------------------------------------
# Operator identity (local user, never root)
# ------------------------------------------------------------
OPERATOR_USER := $(shell id -un)
OPERATOR_GROUP := $(shell id -gn)
OPERATOR_HOME := $(shell getent passwd $(OPERATOR_USER) | cut -d: -f6)

# ------------------------------------------------------------
# Canonical ownership for installed artifacts
# ------------------------------------------------------------
ROOT_UID := 0
ROOT_GID := 0

# ------------------------------------------------------------
# Canonical install paths (tools, scripts, engines)
# ------------------------------------------------------------
INSTALL_PATH        := /usr/local/bin
INSTALL_SBIN_PATH   := /usr/local/sbin

# ---------------------------------------------------------------------------
# Router component constants (Caddy, certs, common.sh)
# ---------------------------------------------------------------------------

# Router connection (single source of truth for deployment)
export ROUTER_ADDR     ?= 10.89.12.1
export ROUTER_USER     ?= julie
export ROUTER_SSH_PORT ?= 2222
export ROUTER_SCRIPTS  ?= /jffs/scripts
export ROUTER_WG_DIR   ?= /jffs/etc/wireguard

# must recompute if user overrides the above
export ROUTER_HOST     := $(ROUTER_USER)@$(ROUTER_ADDR)

ROUTER_CADDYFILE_SRC := $(REPO_ROOT)router/caddy/Caddyfile
ROUTER_CADDYFILE_DST := /jffs/caddy/Caddyfile
ROUTER_CADDY_BIN     := /tmp/mnt/sda/router/bin/caddy

# Router script metadata (owner/group/mode)
ROUTER_SCRIPTS_OWNER := 0
ROUTER_SCRIPTS_GROUP := 0
ROUTER_SCRIPTS_MODE  := 0755

# Local source directory for router scripts
SRC_SCRIPTS := $(REPO_ROOT)router/jffs/scripts

# ------------------------------------------------------------
# Homelab environment file (canonical paths)
# ------------------------------------------------------------

HOMELAB_ENV_SRC := $(REPO_ROOT)config/homelab.env
HOMELAB_ENV_DST := /volume1/homelab/homelab.env

# Installed helpers (authoritative)

CERTS_CREATE        ?= $(ROUTER_SCRIPTS)/certs-create.sh
CERTS_DEPLOY        ?= $(ROUTER_SCRIPTS)/deploy_certificates.sh  # <--- FIX: Correct filename
GEN_CLIENT_CERT     ?= $(ROUTER_SCRIPTS)/generate-client-cert.sh
GEN_CLIENT_WRAPPER  ?= $(ROUTER_SCRIPTS)/gen-client-cert-wrapper.sh

# ------------------------------------------------------------
# Shell platform contract
# ------------------------------------------------------------

COMMON_SH_SRC := $(SRC_SCRIPTS)/common.sh
COMMON_SH_DST := $(ROUTER_SCRIPTS)/common.sh

# ---------------------------------------------------------------------------
# End of Router component constants (Caddy, certs, common.sh)
# ---------------------------------------------------------------------------

# DDNS secret paths (authoritative location only; no secrets or validation here)
DDNS_SECRET_DIR  := /volume1/homelab/secrets
DDNS_SECRET_FILE := $(DDNS_SECRET_DIR)/ddns.conf

# ---------------------------------------------------------------------------
# Network identities (do not alias; roles are distinct by contract)
# ---------------------------------------------------------------------------
export NAS_LAN_IP := 10.89.12.4
export NAS_LAN_IP6 := fd89:7a3b:42c0::4

export GATEWAY_IP  := 10.89.12.1
export LAN_IFACE   := eth0

export ROUTER_LAN_IP := 10.89.12.1

PUBLIC_DNS := 1.1.1.1
SYSTEMD_DIR := /etc/systemd/system
STAMP_DIR := /var/lib/homelab

# Host responsibility (router | service | client)
ROLE ?= service
$(if $(filter $(ROLE),router service client),,$(error Invalid ROLE=$(ROLE)))

APT_CNAME_EXPECTED := bardi.ch

export HOMELAB_ROOT := /volume1/homelab
export WG_ROOT := $(HOMELAB_ROOT)/wireguard
DOCS_DIR := $(HOMELAB_ROOT)/docs
export SECURITY_DIR := $(HOMELAB_ROOT)/security

# Define the worker pool: N-1 if N > 1, else 1 (leaves 1 core for the system/kernel)
N_WORKERS := $(shell nproc | awk '{print ($$1 > 1 ? $$1 - 1 : 1)}')

VERBOSE ?= 0

# ---------------------------------------------------------------------------
# Local tooling root (host-only, disposable, never touches router state)
# ---------------------------------------------------------------------------
TOOLS_DIR ?= $(REPO_ROOT).tools

# ---------------------------------------------------------------------------
# WireGuard subnet derivation (authoritative from wg-interfaces.tsv)
# ---------------------------------------------------------------------------

WG_PLAN_SUBNETS := $(INSTALL_PATH)/wg-plan-subnets.sh

# WireGuard router subnets (derived at runtime; declared here for visibility only)
WG_ROUTER_SUBNET_V4 :=
WG_ROUTER_SUBNET_V6 :=

# --- Global Engine Pointers (V2 ONLY) ---
export INSTALL_FILE_IF_CHANGED     := $(INSTALL_PATH)/install_file_if_changed_v2.sh
INSTALL_FILES_IF_CHANGED           := $(INSTALL_PATH)/install_files_if_changed_v2.sh
INSTALL_URL_FILE_IF_CHANGED        := $(INSTALL_PATH)/install_url_file_if_changed.sh
ENSURE_DIR                         := $(INSTALL_PATH)/ensure_dir.sh

# --- Source Paths (Mappings from Repo to Intent) ---
IFC_V2_SINGLE_SRC := $(REPO_ROOT)scripts/install_file_if_changed_v2.sh
IFC_V2_PLURAL_SRC := $(REPO_ROOT)scripts/install_files_if_changed_v2.sh
IFC_URL_SRC       := $(REPO_ROOT)scripts/install_url_file_if_changed.sh
COMMON_SRC        := $(REPO_ROOT)scripts/common.sh
RUN_ROOT_SRC      := $(REPO_ROOT)scripts/run-as-root.sh

# --- Engine Configuration ---
INSTALL_IF_CHANGED_EXIT_CHANGED ?= 3

# --- Bridge to Homelab Environment ---
# -include allows bootstrapping even if the file doesn't exist yet
-include $(REPO_ROOT)config/homelab.env

# Export key variables to all sub-shells/scripts triggered by Make
export DOMAIN
export ACME_HOME
export ROLE

# Keep the safety guard here so the error happens immediately on any 'make' command
ifeq ($(strip $(DOMAIN)),)
$(error DOMAIN is empty — please define it in config/homelab.env)
endif